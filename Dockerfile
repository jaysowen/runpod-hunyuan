# =============================================================================
# 1) BUILDER STAGE
# =============================================================================
FROM nvidia/cuda:12.6.0-runtime-ubuntu22.04 as builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python-is-python3 \
        git \
        build-essential \
        python3-dev \
        curl \
        wget \
        gcc \
        g++ \
        make \
        cmake \
    && rm -rf /var/lib/apt/lists/*

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    CC=gcc \
    CXX=g++

# Clone ComfyUI (source only; no final environment here)
WORKDIR /
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git

# =============================================================================
# 2) FINAL STAGE
# =============================================================================
FROM nvidia/cuda:12.6.0-runtime-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python-is-python3 \
    git \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1-mesa-glx \
    wget \
    curl \
    openssh-server \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# If you need runtime compilation of certain nodes, ALSO add:
# build-essential, python3-dev, etc.
# RUN apt-get update && apt-get install -y build-essential python3-dev && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip3 install --no-cache-dir --upgrade pip

# --- Install PyTorch 2.6 for CUDA 12.6 ---
# The official command from pytorch.org for 2.6 stable, Linux, pip, Python, CUDA 12.6:
RUN pip3 install --no-cache-dir torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu126

# Copy ComfyUI from builder
COPY --from=builder /ComfyUI /ComfyUI

# Install ComfyUI requirements
WORKDIR /ComfyUI
RUN pip3 install --no-cache-dir -r requirements.txt

# Install other Python packages (e.g., Jupyter, accelerate, etc.)
RUN pip3 install --no-cache-dir \
    jupyterlab \
    notebook \
    ipykernel \
    ipywidgets \
    jupyter_server \
    jupyterlab_widgets \
    triton \
    sageattention \
    safetensors \
    aiohttp \
    accelerate \
    pyyaml \
    torchsde \
    opencv-python

# Install custom nodes
WORKDIR /ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone --depth 1 https://github.com/facok/ComfyUI-HunyuanVideoMultiLora.git && \
    git clone --depth 1 https://github.com/sipherxyz/comfyui-art-venture.git && \
    git clone --depth 1 https://github.com/theUpsider/ComfyUI-Logic.git && \
    git clone --depth 1 https://github.com/Smirnov75/ComfyUI-mxToolkit.git && \
    git clone --depth 1 https://github.com/alt-key-project/comfyui-dream-project.git && \
    git clone --depth 1 https://github.com/Jonseed/ComfyUI-Detail-Daemon.git && \
    git clone --depth 1 https://github.com/ShmuelRonen/ComfyUI-ImageMotionGuider.git && \
    git clone --depth 1 https://github.com/BlenderNeko/ComfyUI_Noise.git && \
    git clone --depth 1 https://github.com/chrisgoringe/cg-noisetools.git && \
    git clone --depth 1 https://github.com/cubiq/ComfyUI_essentials.git && \
    git clone --depth 1 https://github.com/chrisgoringe/cg-use-everywhere.git && \
    git clone --depth 1 https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git && \
    git clone --depth 1 https://github.com/pharmapsychotic/comfy-cliption.git && \
    git clone --depth 1 https://github.com/darkpixel/darkprompts.git && \
    git clone --depth 1 https://github.com/Koushakur/ComfyUI-DenoiseChooser.git && \
    git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git && \
    git clone --depth 1 https://github.com/giriss/comfy-image-saver.git && \
    git clone --depth 1 https://github.com/11dogzi/Comfyui-ergouzi-Nodes.git && \
    git clone --depth 1 https://github.com/jamesWalker55/comfyui-various.git && \
    git clone --depth 1 https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git && \
    git clone --depth 1 https://github.com/M1kep/ComfyLiterals.git && \
    git clone --depth 1 https://github.com/welltop-cn/ComfyUI-TeaCache.git && \
    git clone --depth 1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone --depth 1 https://github.com/chengzeyi/Comfy-WaveSpeed.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth 1 https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone --depth 1 https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth 1 https://github.com/WASasquatch/was-node-suite-comfyui.git && \
    git clone --depth 1 https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone --depth 1 https://github.com/Amorano/Jovimetrix.git

# Install build requirements for custom nodes that need them
RUN for dir in */; do \
    if [ -f "${dir}requirements.txt" ]; then \
        echo "Installing build requirements for ${dir}..." && \
        pip3 install --no-cache-dir -r "${dir}requirements.txt" || true; \
    fi; \
    if [ -f "${dir}install.py" ]; then \
        echo "Running install script for ${dir}..." && \
        python3 "${dir}install.py" || true; \
    fi \
    done

# Copy workflow files
COPY AllinOneUltra1.2.json AllinOneUltra1.3.json /ComfyUI/user/default/workflows/

# Copy scripts
COPY scripts/*.sh /
RUN chmod +x /*.sh

# (Optional) Create necessary directories
# RUN mkdir -p /workspace/logs /workspace/ComfyUI/models/{unet,text_encoders,clip_vision,vae,loras}

# Switch back to root or a working directory
WORKDIR /

CMD ["/start.sh"]
