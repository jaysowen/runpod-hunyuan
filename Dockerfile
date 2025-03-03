# =============================================================================
# 1) BUILDER STAGE
# =============================================================================
FROM nvidia/cuda:12.5.0-runtime-ubuntu22.04 as builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        git \
        build-essential \
        curl \
        gcc \
        g++ \
        make \
        cmake \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Install Miniconda and Python 3.12
RUN curl -fsSL -v -o ~/miniconda.sh -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    chmod +x ~/miniconda.sh && \
    ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh

# Add conda to path
ENV PATH /opt/conda/bin:$PATH

# Create Python 3.12 environment
RUN conda install -y python=3.12 pip && \
    conda clean -ya

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    CC=gcc \
    CXX=g++

# Clone ComfyUI (source only; no final environment here)
WORKDIR /
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
RUN git clone --depth 1 https://github.com/zanllp/sd-webui-infinite-image-browsing.git


# =============================================================================
# 2) FINAL STAGE
# =============================================================================
FROM nvidia/cuda:12.5.0-devel-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && \
    # Pre-accept the Microsoft font EULA
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections && \
    apt-get install -y --no-install-recommends \
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
        g++ \
        ca-certificates \
        dos2unix \
        libegl1 \
        libegl-mesa0 \
        libgles2-mesa-dev \
        libglvnd0 \
        libglx0 \
        libopengl0 \
        x11-xserver-utils \
        ttf-mscorefonts-installer \
        fonts-liberation \
        fonts-dejavu \
        fontconfig && \
    rm -rf /var/lib/apt/lists/*

# Set OpenGL environment variables -  libEGL.so not loaded
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics
ENV DISPLAY=:99

# Install Miniconda and Python 3.12
RUN curl -fsSL -v -o ~/miniconda.sh -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    chmod +x ~/miniconda.sh && \
    ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh

# Add conda to path
ENV PATH /opt/conda/bin:$PATH

# Create Python 3.12 environment
RUN conda install -y python=3.12 pip && \
    conda clean -ya

# Add environment variables for compilation
ENV CC=gcc \
    CXX=g++

# Upgrade pip
RUN pip install --no-cache-dir --upgrade pip

# --- Install PyTorch for CUDA ---
RUN pip install --no-cache-dir torch torchvision torchaudio

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
RUN git clone --depth 1 https://github.com/chrisgoringe/cg-use-everywhere.git && \
    git clone --depth 1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth 1 https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth 1 https://github.com/WASasquatch/was-node-suite-comfyui.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone --depth 1 https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone --depth 1 https://github.com/cubiq/ComfyUI_essentials && \
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-WanVideoWrapper.git

# Install requirements for custom nodes (if any)
RUN for dir in */; do \
    if [ -f "${dir}requirements.txt" ]; then \
        echo "Installing requirements for ${dir}..." && \
        pip install --no-cache-dir -r "${dir}requirements.txt" || true; \
    fi \
    done


# Copy workflow files
COPY comfy-workflows/*.json /ComfyUI/user/default/workflows/


# Copy sd-webui from builder
COPY --from=builder /sd-webui-infinite-image-browsing /sd-webui-infinite-image-browsing

# Install sd-webui requirements
WORKDIR /sd-webui-infinite-image-browsing
RUN pip install --no-cache-dir -r requirements.txt

# Copy all scripts
COPY scripts/*.sh /

# Copy files to container root directory
COPY manage-files/download-files.sh /
COPY manage-files/files.txt /

# Also create workspace directory structure
RUN mkdir -p /workspace

# Copy files to container root directory
COPY manage-files/download-files.sh /workspace/
COPY manage-files/files.txt /workspace/

RUN dos2unix /*.sh && \
    dos2unix /workspace/*.sh && \
    chmod +x /*.sh && \
    chmod +x /workspace/*.sh

CMD ["/start.sh"]