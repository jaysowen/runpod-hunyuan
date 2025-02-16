# Build stage for installing dependencies and ComfyUI
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
    torch==2.2.1 \
    torchvision \
    torchaudio \
    --extra-index-url https://download.pytorch.org/whl/cu124 && \
    pip3 install --no-cache-dir \
    jupyterlab \
    jupyterlab_widgets \
    ipykernel \
    ipywidgets \
    aiohttp

# Clone and install ComfyUI
WORKDIR /build
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install --no-cache-dir -r requirements.txt && \
    mkdir -p models/{checkpoints,text_encoder,clip_vision,vae}

# Clone and install ComfyUI-Manager
RUN cd /build/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    pip install --no-cache-dir -r requirements.txt

# Download specific model file
RUN cd /build/ComfyUI/models/vae && \
    wget -q --show-progress \
    https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors

# Runtime stage
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

# Create workspace and copy ComfyUI from builder
WORKDIR /workspace
COPY --from=builder /build/ComfyUI ./ComfyUI
COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages

# Create logs directory
RUN mkdir -p /workspace/logs

# Create startup script
RUN echo '#!/bin/bash\n\
cd /workspace/ComfyUI\n\
python main.py --listen --port 8188 --enable-cors-header --verbose $COMFYUI_EXTRA_ARGS\n\
' > /start.sh && \
    chmod +x /start.sh

WORKDIR /workspace
CMD ["/start.sh"]