# Build stage
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04 as builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Combine all ARGs
ARG PYTHON_VERSION=3.12.1
ARG TORCH_VERSION=2.2.1
ARG CUDA_VERSION=cu124
ARG COMFYUI_VERSION=latest

# Install essential packages in a single layer
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    git wget curl \
    && rm -rf /var/lib/apt/lists/*

# Create and activate venv directly in workspace
RUN python3 -m venv /workspace/venv
ENV PATH="/workspace/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install Python packages in a single layer with buildkit cache
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -U pip setuptools wheel && \
    pip install torch==${TORCH_VERSION} torchvision torchaudio \
    --extra-index-url https://download.pytorch.org/whl/${CUDA_VERSION} && \
    pip install jupyterlab jupyterlab_widgets ipykernel ipywidgets aiohttp

# Install ComfyUI with cache mounting
WORKDIR /
RUN --mount=type=cache,target=/root/.cache/pip \
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    if [ "${COMFYUI_VERSION}" != "latest" ]; then \
        git fetch --depth=1 origin tag ${COMFYUI_VERSION} && \
        git checkout ${COMFYUI_VERSION}; \
    fi && \
    pip install -r requirements.txt

# Install core custom nodes with shallow clones
WORKDIR /ComfyUI/custom_nodes
RUN git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth=1 https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone --depth=1 https://github.com/crystian/ComfyUI-Crystools.git

# Install requirements for core nodes with cache
RUN --mount=type=cache,target=/root/.cache/pip \
    cd /ComfyUI/custom_nodes && \
    find . -name "requirements.txt" -exec pip install -r {} \;

# Run install scripts for core nodes if they exist
RUN cd /ComfyUI/custom_nodes && \
    for script in */install.py; do \
        if [ -f "$script" ]; then \
            python "$script"; \
        fi \
    done

# Runtime stage
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Install runtime dependencies with cache
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    rsync openssh-server ffmpeg libgl1 libglib2.0-0 wget \
    && rm -rf /var/lib/apt/lists/*

# Set runtime environment variables
ENV PYTHONUNBUFFERED=True \
    DEBIAN_FRONTEND=noninteractive \
    LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu \
    PATH="/workspace/venv/bin:$PATH"

# Copy the built venv and ComfyUI from builder
COPY --from=builder /workspace/venv /workspace/venv
COPY --from=builder /ComfyUI /workspace/ComfyUI

# Create necessary directories
RUN mkdir -p /workspace/ComfyUI/models/{checkpoints,text_encoder,clip_vision,vae} \
    /workspace/logs

# Copy configuration and scripts
COPY scripts/start.sh scripts/pre_start.sh scripts/install_nodes.sh scripts/download_models.sh /
RUN chmod +x /start.sh /pre_start.sh /install_nodes.sh /download_models.sh

# Welcome message
COPY logo/runpod.txt /etc/runpod.txt
RUN echo 'cat /etc/runpod.txt' >> /root/.bashrc && \
    echo 'echo -e "\nFor detailed documentation and guides, please visit:\n\033[1;34mhttps://docs.runpod.io/\033[0m and \033[1;34mhttps://blog.runpod.io/\033[0m\n\n"' >> /root/.bashrc

WORKDIR /workspace

CMD ["/start.sh"]