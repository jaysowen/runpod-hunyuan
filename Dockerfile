# =============================================================================
# 1) BUILDER STAGE
# =============================================================================
FROM nvidia/cuda:12.6.0-runtime-ubuntu22.04 as builder

# Install build dependencies and Python 3.12
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        gpg-agent \
        wget \
        git \
        build-essential \
        curl \
        gcc \
        g++ \
        make \
        cmake && \
    # Add deadsnakes PPA for Python 3.12
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.12 \
        python3.12-dev \
        python3.12-venv \
        python3.12-distutils && \
    # Install pip for Python 3.12
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 && \
    # Create symlinks
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 && \
    rm -rf /var/lib/apt/lists/*

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
FROM nvidia/cuda:12.6.0-devel-ubuntu22.04

# Install runtime dependencies and Python 3.12
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        gpg-agent \
        wget \
        git \
        ffmpeg \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender-dev \
        libgl1-mesa-glx \
        curl \
        openssh-server \
        nodejs \
        npm \
        build-essential \
        nvidia-cuda-dev \
        gcc \
        g++ && \
    # Add deadsnakes PPA for Python 3.12
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.12 \
        python3.12-dev \
        python3.12-venv \
        python3.12-distutils && \
    # Install pip for Python 3.12
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 && \
    # Create symlinks
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 && \
    rm -rf /var/lib/apt/lists/*

# Add environment variables for compilation
ENV CC=gcc \
    CXX=g++

# Upgrade pip
RUN pip install --no-cache-dir --upgrade pip

# --- Install PyTorch 2.6 for CUDA 12.6 ---
RUN pip install --no-cache-dir torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu126

# Copy ComfyUI from builder
COPY --from=builder /ComfyUI /ComfyUI

# Install ComfyUI requirements
WORKDIR /ComfyUI
RUN pip install --no-cache-dir -r requirements.txt

# Install other Python packages
RUN pip install --no-cache-dir \
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
    opencv-python \
    gdown

# Clone custom nodes
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
    git clone --depth 1 https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth 1 https://github.com/WASasquatch/was-node-suite-comfyui.git && \
    git clone --depth 1 https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone --depth 1 https://github.com/Amorano/Jovimetrix.git

# Install requirements for custom nodes (if any)
RUN for dir in */; do \
    if [ -f "${dir}requirements.txt" ]; then \
        echo "Installing requirements for ${dir}..." && \
        pip install --no-cache-dir -r "${dir}requirements.txt" || true; \
    fi \
    done

# Copy workflow files
COPY AllinOneUltra1.2.json AllinOneUltra1.3.json /ComfyUI/user/default/workflows/

# Copy scripts
COPY scripts/*.sh /
RUN chmod +x /*.sh

WORKDIR /

CMD ["/start.sh"]