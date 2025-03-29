# =============================================================================
# 1) BUILDER STAGE
# =============================================================================
FROM nvidia/cuda:12.5.0-runtime-ubuntu22.04 AS builder

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
ENV PATH=/opt/conda/bin:$PATH

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
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# =============================================================================
# 2) FINAL STAGE - Only Jupyter pip packages removed
# =============================================================================
FROM nvidia/cuda:12.5.0-devel-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && \
    # Pre-accept the Microsoft font EULA
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
        libglx0 && \
    rm -rf /var/lib/apt/lists/*

# Set OpenGL environment variables
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics

# Install Miniconda and Python 3.12
RUN curl -fsSL -v -o ~/miniconda.sh -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    chmod +x ~/miniconda.sh && \
    ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh

# Add conda to path
ENV PATH=/opt/conda/bin:$PATH

# Create Python 3.12 environment
RUN conda install -y python=3.12 pip && \
    conda clean -ya

# Add environment variables for compilation
ENV CC=gcc \
    CXX=g++

# Upgrade pip - UNCHANGED
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
    triton \
    sageattention \
    safetensors \
    aiohttp \
    accelerate \
    pyyaml \
    torchsde \
    opencv-python \
    gdown

# Install runpod
RUN pip install runpod requests

RUN pip install b2sdk

# Clone custom nodes
WORKDIR /ComfyUI/custom_nodes
RUN git clone https://github.com/chrisgoringe/cg-use-everywhere.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/cubiq/ComfyUI_essentials && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    git clone https://github.com/chflame163/ComfyUI_LayerStyle.git && \
    git clone https://github.com/kijai/ComfyUI-Florence2.git && \
    git clone https://github.com/kijai/ComfyUI-segment-anything-2.git && \
    git clone https://github.com/storyicon/comfyui_segment_anything.git && \
    git clone https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git && \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git

# Install requirements for custom nodes (if any)
RUN for dir in */; do \
    if [ -f "${dir}requirements.txt" ]; then \
        echo "Installing requirements for ${dir}..." && \
        pip install --no-cache-dir -r "${dir}requirements.txt" || true; \
    fi \
    done

# Copy workflow files
COPY comfy-workflows/*.json /ComfyUI/user/default/workflows/

# Copy all scripts 
COPY scripts/rp_handler.py /
COPY scripts/*.sh /

# Copy files to container root directory
COPY manage-files/download-files.sh /
COPY manage-files/files.txt /

# Also create workspace directory structure
RUN mkdir -p /workspace

# Copy files to container root directory
COPY manage-files/download-files.sh /workspace/
COPY manage-files/files.txt /workspace/

# Permissions and line ending fixes
RUN dos2unix /*.sh && \
    dos2unix /workspace/*.sh && \
    chmod +x /*.sh && \
    chmod +x /workspace/*.sh

# Default command
CMD ["/start.sh"]
