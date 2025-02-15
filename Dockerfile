# Build stage for Python packages
FROM python:3.12-slim as python-builder

WORKDIR /build
RUN python -m venv /build/venv
ENV PATH="/build/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install Python packages without CUDA first
RUN pip install --no-cache-dir \
    jupyterlab jupyterlab_widgets ipykernel ipywidgets aiohttp && \
    find /build/venv -type d -name "__pycache__" -exec rm -rf {} + || true

# CUDA build stage
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04 as cuda-builder

# Copy Python venv from previous stage
COPY --from=python-builder /build/venv /build/venv
ENV PATH="/build/venv/bin:$PATH"

# Install only essential build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip git wget && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Install PyTorch with CUDA
ARG TORCH_VERSION=2.2.1
ARG CUDA_VERSION=cu124
RUN pip install --no-cache-dir \
    torch==${TORCH_VERSION} torchvision torchaudio \
    --extra-index-url https://download.pytorch.org/whl/${CUDA_VERSION} && \
    rm -rf /root/.cache/pip/*

# Install ComfyUI and essential nodes
WORKDIR /build
RUN git clone --depth=1 --single-branch --branch master \
    https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install --no-cache-dir -r requirements.txt && \
    rm -rf .git

# Install only the most essential custom nodes
WORKDIR /build/ComfyUI/custom_nodes
RUN git clone --depth=1 --single-branch https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    cd ComfyUI-Impact-Pack && \
    pip install --no-cache-dir -r requirements.txt && \
    rm -rf .git

# Final runtime stage
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip ffmpeg libgl1 libglib2.0-0 wget openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Set runtime environment variables
ENV PATH="/workspace/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

# Copy only necessary files from builder stages
COPY --from=cuda-builder /build/venv /workspace/venv
COPY --from=cuda-builder /build/ComfyUI /workspace/ComfyUI

# Create model directories
RUN mkdir -p /workspace/ComfyUI/models/{checkpoints,text_encoder,clip_vision,vae} \
    /workspace/logs

# Copy essential scripts
COPY scripts/start.sh scripts/pre_start.sh scripts/install_nodes.sh scripts/download_models.sh /
RUN chmod +x /start.sh /pre_start.sh /install_nodes.sh /download_models.sh

WORKDIR /workspace
CMD ["/start.sh"]