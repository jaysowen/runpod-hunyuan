# Build stage for Python packages
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04 as builder

# Install Python and build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3.10-venv \
    python3-pip \
    git \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    wget \
    openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Create virtual environment
RUN python3.10 -m venv /workspace/venv
ENV PATH="/workspace/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install Python packages
RUN pip install --no-cache-dir \
    jupyterlab \
    jupyterlab_widgets \
    ipykernel \
    ipywidgets \
    aiohttp && \
    pip install --no-cache-dir \
    torch==2.2.1 \
    torchvision \
    torchaudio \
    --extra-index-url https://download.pytorch.org/whl/cu124

# Create workspace structure
RUN mkdir -p /workspace/ComfyUI

# Install ComfyUI
WORKDIR /workspace
RUN git clone --depth=1 --single-branch --branch master \
    https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI_temp && \
    cp -r /workspace/ComfyUI_temp/* /workspace/ComfyUI/ && \
    rm -rf /workspace/ComfyUI_temp && \
    cd /workspace/ComfyUI && \
    pip install --no-cache-dir -r requirements.txt

# Install Impact Pack
RUN mkdir -p /workspace/ComfyUI/custom_nodes && \
    cd /workspace/ComfyUI/custom_nodes && \
    git clone --depth=1 --single-branch https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    cd ComfyUI-Impact-Pack && \
    pip install --no-cache-dir -r requirements.txt

# Final runtime stage
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3.10-venv \
    python3-pip \
    git \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    wget \
    openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Create symlinks
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/python3.10 /usr/bin/python3

# Set environment variables
ENV PATH="/workspace/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

# Create workspace structure
RUN mkdir -p /workspace

# Copy files from builder
COPY --from=builder /workspace/venv /workspace/venv
COPY --from=builder /workspace/ComfyUI /workspace/ComfyUI

# Create model directories
RUN mkdir -p /workspace/ComfyUI/models/{checkpoints,text_encoder,clip_vision,vae} \
    /workspace/logs

# Copy essential scripts
COPY scripts/start.sh scripts/pre_start.sh scripts/install_nodes.sh scripts/download_models.sh /
RUN chmod +x /start.sh /pre_start.sh /install_nodes.sh /download_models.sh

WORKDIR /workspace
CMD ["/start.sh"]