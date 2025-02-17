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
    openssh-server \
    build-essential \
    python3-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create symlinks for Python
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/python3.10 /usr/bin/python3

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install Python packages
RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir \
    jupyterlab \
    jupyterlab_widgets \
    ipykernel \
    ipywidgets \
    aiohttp \
    triton \
    sageattention

# Install PyTorch
RUN pip3 install --no-cache-dir \
    torch==2.2.1 \
    torchvision \
    torchaudio \
    --extra-index-url https://download.pytorch.org/whl/cu124

# Clone ComfyUI to root directory
WORKDIR /
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install --no-cache-dir -r requirements.txt

# Install core custom nodes during build
WORKDIR /ComfyUI/custom_nodes
RUN for repo in \
    "https://github.com/ltdrdata/ComfyUI-Manager.git" \
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git" \
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" \
    "https://github.com/WASasquatch/was-node-suite-comfyui.git" \
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"; \
    do \
        dir_name=$(basename $repo .git); \
        git clone --depth 1 $repo && \
        if [ -f "$dir_name/requirements.txt" ]; then \
            pip install --no-cache-dir -r "$dir_name/requirements.txt" || true; \
        fi; \
    done && \
    pip cache purge

# Copy all scripts
COPY scripts/start.sh /start.sh
COPY scripts/pre_start.sh /pre_start.sh
COPY scripts/download_models.sh /download_models.sh
COPY scripts/install_nodes.sh /install_nodes.sh

# Make scripts executable
RUN chmod +x /*.sh

# Create workspace and logs directory
RUN mkdir -p /workspace/logs

CMD ["/start.sh"]