# =============================================================================
# 1) BUILDER STAGE
# =============================================================================
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04 AS builder

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
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && \
    # Pre-accept the Microsoft font EULA
    apt-get install -y --no-install-recommends \
        wget \
        git \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libgl1-mesa-glx \
        curl \
        ca-certificates \
        dos2unix \
        libegl1 \
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

# --- Install PyTorch for CUDA 12.4 (Specific Version) ---
# Verify torchvision/torchaudio compatibility if necessary
ENV PYTORCH_VERSION=2.5.1
ENV TORCHVISION_VERSION=0.20.1
ENV TORCHAUDIO_VERSION=2.5.1

RUN echo "Installing PyTorch ${PYTORCH_VERSION}, torchvision ${TORCHVISION_VERSION}, torchaudio ${TORCHAUDIO_VERSION} for CUDA 12.4" && \
    pip install --no-cache-dir \
        torch==${PYTORCH_VERSION} \
        torchvision==${TORCHVISION_VERSION} \
        torchaudio==${TORCHAUDIO_VERSION} \
        --index-url https://download.pytorch.org/whl/cu124

# Copy ComfyUI from builder
COPY --from=builder /ComfyUI /ComfyUI

# Install ComfyUI requirements
WORKDIR /ComfyUI
RUN pip install --no-cache-dir -r requirements.txt

RUN pip install --no-cache-dir --upgrade "Pillow>=10.3.0"

# Install other Python packages
RUN pip install --no-cache-dir \
    triton \
    sageattention \
    safetensors \
    aiohttp \
    accelerate \
    pyyaml \
    torchsde \
    opencv-python

# Install runpod and B2 SDK (needed for uploads)
RUN pip install runpod requests b2sdk

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Clone custom nodes
WORKDIR /ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone https://github.com/chflame163/ComfyUI_LayerStyle.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/SeanScripts/ComfyUI-Unload-Model.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/orssorbit/ComfyUI-wanBlockswap.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/cubiq/ComfyUI_essentials.git && \
    git clone https://github.com/pollockjj/ComfyUI-MultiGPU.git && \
    git clone https://github.com/Smirnov75/ComfyUI-mxToolkit.git && \
    git clone https://github.com/asagi4/ComfyUI-Adaptive-Guidance.git && \
    git clone https://github.com/Flow-two/ComfyUI-WanStartEndFramesNative.git && \
    git clone https://github.com/BigStationW/flowmatch_scheduler-comfyui.git
    
# Install ComfyUI-VideoHelperSuite
WORKDIR /ComfyUI/custom_nodes/ComfyUI-VideoHelperSuite
RUN pip install --no-cache-dir -r requirements.txt

# Install requirements for custom nodes (if any)
# Reverted to installing requirements for each node individually, ignoring errors.
# This allows the build to complete even if some dependencies conflict or fail,
# potentially leading to runtime issues for specific nodes.
RUN for dir in /ComfyUI/custom_nodes/*/; do \
    if [ -f "${dir}requirements.txt" ]; then \
        echo "Installing requirements for ${dir}..." && \
        pip install --no-cache-dir -r "${dir}requirements.txt" || echo "WARNING: Failed to install requirements for ${dir}, continuing..."; \
    fi \
    done

# Copy scripts to container root
COPY scripts/rp_handler.py /
COPY scripts/*.sh /

# Also create workspace directory structure
RUN mkdir -p /workspace

# Copy files to container root directory - REMOVED, no longer needed
# COPY manage-files/download-files.sh /workspace/
# COPY manage-files/files.txt /workspace/

# Permissions and line ending fixes
RUN dos2unix /start.sh /rp_handler.py /*.sh && \
    # dos2unix /workspace/*.sh && # Removed as no sh scripts copied to workspace
    chmod +x /start.sh /rp_handler.py /*.sh
    # chmod +x /workspace/*.sh # Removed

# Default command
CMD ["/start.sh"]
