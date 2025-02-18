# Build stage
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04 as builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    git \
    build-essential \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Create symlinks for Python
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/python3.10 /usr/bin/python3

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install PyTorch and core dependencies
RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir torch==2.2.1 torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124 && \
    pip3 install --no-cache-dir jupyterlab jupyterlab_widgets ipykernel ipywidgets aiohttp triton sageattention

# Clone and setup ComfyUI
WORKDIR /
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install --no-cache-dir -r requirements.txt

# Install ALL custom nodes during build
WORKDIR /ComfyUI/custom_nodes

# Video and Frame Processing
RUN git clone --depth 1 https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone --depth 1 https://github.com/facok/ComfyUI-HunyuanVideoMultiLora.git && \
    # Workflow Tools
    git clone --depth 1 https://github.com/Amorano/Jovimetrix.git && \
    git clone --depth 1 https://github.com/sipherxyz/comfyui-art-venture.git && \
    git clone --depth 1 https://github.com/theUpsider/ComfyUI-Logic.git && \
    git clone --depth 1 https://github.com/Smirnov75/ComfyUI-mxToolkit.git && \
    git clone --depth 1 https://github.com/alt-key-project/comfyui-dream-project.git && \
    # Image Enhancement
    git clone --depth 1 https://github.com/Jonseed/ComfyUI-Detail-Daemon.git && \
    git clone --depth 1 https://github.com/ShmuelRonen/ComfyUI-ImageMotionGuider.git && \
    # Noise Tools
    git clone --depth 1 https://github.com/BlenderNeko/ComfyUI_Noise.git && \
    git clone --depth 1 https://github.com/chrisgoringe/cg-noisetools.git && \
    # Utility Nodes
    git clone --depth 1 https://github.com/cubiq/ComfyUI_essentials.git && \
    git clone --depth 1 https://github.com/chrisgoringe/cg-use-everywhere.git && \
    git clone --depth 1 https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git && \
    # Special Purpose
    git clone --depth 1 https://github.com/pharmapsychotic/comfy-cliption.git && \
    git clone --depth 1 https://github.com/darkpixel/darkprompts.git && \
    git clone --depth 1 https://github.com/Koushakur/ComfyUI-DenoiseChooser.git && \
    git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git && \
    git clone --depth 1 https://github.com/giriss/comfy-image-saver.git && \
    # Additional Utilities
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
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth 1 https://github.com/WASasquatch/was-node-suite-comfyui.git

# Install requirements for all nodes
RUN for dir in */; do \
    if [ -f "${dir}requirements.txt" ]; then \
        echo "Installing requirements for ${dir}..." && \
        pip install --no-cache-dir -r "${dir}requirements.txt" || true; \
    fi; \
    if [ -f "${dir}install.py" ]; then \
        echo "Running install script for ${dir}..." && \
        python "${dir}install.py" || true; \
    fi \
    done

# Final stage
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Install runtime dependencies including Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    git \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    wget \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Create Python symlinks in final stage
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/python3.10 /usr/bin/python3

# Copy Python environment from builder
COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages
COPY --from=builder /ComfyUI /ComfyUI

# Copy workflow files
COPY AllinOneUltra1.2.json AllinOneUltra1.3.json /ComfyUI/user/default/workflows/

# Copy scripts
COPY scripts/*.sh /
RUN chmod +x /*.sh

# Create necessary directories
RUN mkdir -p /workspace/logs /workspace/ComfyUI/models/{unet,text_encoders,clip_vision,vae,loras}

CMD ["/start.sh"]