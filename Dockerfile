# Build stage
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04 as builder

# Install Python and build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    git \
    wget && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Set Python environment variables
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install Python packages
RUN pip3 install --no-cache-dir \
    jupyterlab \
    jupyterlab_widgets \
    ipykernel \
    ipywidgets \
    aiohttp && \
    pip3 install --no-cache-dir \
    torch==2.2.1 \
    torchvision \
    torchaudio \
    --extra-index-url https://download.pytorch.org/whl/cu124

COPY --chmod=755 start.sh /start.sh
COPY --chmod=755 comfyui-on-workspace.sh /comfyui-on-workspace.sh

# First clone ComfyUI fully
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install --no-cache-dir -r requirements.txt
    

# # Then create model directories inside the existing ComfyUI directory
# RUN cd /workspace/ComfyUI && \
#     mkdir -p models/checkpoints && \
#     mkdir -p models/text_encoder && \
#     mkdir -p models/clip_vision && \
#     mkdir -p models/vae

# # Install ComfyUI-Manager
# RUN cd /workspace/ComfyUI/custom_nodes && \
#     git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
#     cd ComfyUI-Manager && \
#     pip install --no-cache-dir -r requirements.txt || true

# Final runtime stage
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    git \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    wget \
    openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Create symlinks for Python
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/python3.10 /usr/bin/python3

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Create workspace
WORKDIR /workspace

# Copy the entire ComfyUI directory including all files and models directories
COPY --from=builder /workspace/ComfyUI /workspace/ComfyUI
COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages

# Create logs directory
RUN mkdir -p /workspace/logs

# Copy essential scripts
# COPY scripts/start.sh scripts/pre_start.sh scripts/install_nodes.sh scripts/download_models.sh /
# RUN chmod +x /start.sh /pre_start.sh /install_nodes.sh /download_models.sh

WORKDIR /workspace
CMD ["/start.sh"]