FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel-ubuntu22.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set environment variables
ENV SHELL=/bin/bash
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all

# System setup and dependencies
RUN apt-get update --yes && \
    apt-get upgrade --yes && \
    apt install --yes --no-install-recommends \
    git \
    wget \
    curl \
    bash \
    libgl1 \
    software-properties-common \
    openssh-server \
    ffmpeg \
    nodejs \
    npm \
    dos2unix \
    build-essential \
    libcudnn8 && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Create and activate virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install base Python packages
RUN pip install --upgrade --no-cache-dir pip && \
    pip install --upgrade setuptools wheel && \
    pip install numpy==1.23.5 && \
    pip install --no-cache-dir triton sageattention

# Pre-install some key dependencies
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 && \
    pip install --no-cache-dir moviepy opencv-python pillow

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Create workspace directory and clone ComfyUI
WORKDIR /workspace
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# Install ComfyUI requirements separately
WORKDIR /workspace/ComfyUI
RUN pip install --no-cache-dir -r requirements.txt

# Create custom_nodes directory
RUN mkdir -p custom_nodes
WORKDIR /workspace/ComfyUI/custom_nodes

# Clone core custom nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/BlenderNeko/ComfyUI_Noise.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git

# Clone utility nodes
RUN git clone https://github.com/chrisgoringe/cg-noisetools.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git

# Clone enhancement nodes
RUN git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/cubiq/ComfyUI_essentials.git && \
    git clone https://github.com/chrisgoringe/cg-use-everywhere.git && \
    git clone https://github.com/Jonseed/ComfyUI-Detail-Daemon.git && \
    git clone https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git && \
    git clone https://github.com/chengzeyi/Comfy-WaveSpeed.git

# Clone workflow nodes
RUN git clone https://github.com/Amorano/Jovimetrix.git && \
    git clone https://github.com/sipherxyz/comfyui-art-venture.git && \
    git clone https://github.com/theUpsider/ComfyUI-Logic.git && \
    git clone https://github.com/Smirnov75/ComfyUI-mxToolkit.git && \
    git clone https://github.com/alt-key-project/comfyui-dream-project.git

# Clone special purpose nodes
RUN git clone https://github.com/pharmapsychotic/comfy-cliption.git && \
    git clone https://github.com/darkpixel/darkprompts.git && \
    git clone https://github.com/Koushakur/ComfyUI-DenoiseChooser.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git && \
    git clone https://github.com/giriss/comfy-image-saver.git

# Clone additional nodes
RUN git clone https://github.com/facok/ComfyUI-HunyuanVideoMultiLora.git && \
    git clone https://github.com/11dogzi/Comfyui-ergouzi-Nodes.git && \
    git clone https://github.com/jamesWalker55/comfyui-various.git && \
    git clone https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git && \
    git clone https://github.com/ShmuelRonen/ComfyUI-ImageMotionGuider.git && \
    git clone https://github.com/M1kep/ComfyLiterals.git && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui && \
    git clone https://github.com/welltop-cn/ComfyUI-TeaCache.git

# Install requirements for custom nodes
WORKDIR /workspace/ComfyUI
RUN for req in $(find custom_nodes -name "requirements.txt"); do \
    echo "Installing requirements from $req"; \
    pip install --no-cache-dir -r "$req" || echo "Failed to install some requirements from $req"; \
    done

# Create necessary directories
RUN mkdir -p models/{unet,text_encoders,vae,upscale,loras} && \
    mkdir -p user/default/workflows && \
    mkdir -p /workspace/logs

# Copy workflow files
# COPY AllinOneUltra1.3.json /workspace/ComfyUI/user/default/workflows/
COPY AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/

# Copy startup scripts with proper permissions
COPY --chmod=755 start.sh /start.sh
COPY --chmod=755 setup.sh /workspace/setup.sh
COPY --chmod=755 download-fix.sh /workspace/download-fix.sh

# Remove any problematic extensions
RUN rm -rf /workspace/ComfyUI/web/extensions/EG_GN_NODES || true

WORKDIR /workspace

ENTRYPOINT ["/start.sh"]