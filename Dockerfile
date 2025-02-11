FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# System setup and additional dependencies
RUN apt-get update --yes && \
    apt-get upgrade --yes && \
    apt install --yes --no-install-recommends \
    git \
    wget \
    curl \
    libgl1 \
    ffmpeg \
    nodejs \
    npm \
    dos2unix && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Create workspace directory
WORKDIR /workspace

# Clone and set up ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# Install ComfyUI requirements
RUN pip install -r requirements.txt
RUN pip install moviepy opencv-python pillow

# Create custom_nodes directory and clone repositories
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

# Install requirements for all custom nodes
WORKDIR /workspace/ComfyUI
RUN find custom_nodes -name requirements.txt -exec pip install -r {} \;

# Create model directories
RUN mkdir -p models/{unet,text_encoders,vae,upscale,loras}

# Create workflows directory
RUN mkdir -p /workspace/ComfyUI/user/default/workflows

# Copy workflow files
# COPY AllinOneUltra1.3.json /workspace/ComfyUI/user/default/workflows/
COPY AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/

# Copy startup scripts
COPY start.sh /workspace/start.sh
COPY setup.sh /workspace/setup.sh
COPY download-fix.sh /workspace/download-fix.sh

# Fix line endings and set permissions
RUN tr -d '\r' < /workspace/start.sh > /workspace/start.sh.tmp && \
    mv /workspace/start.sh.tmp /workspace/start.sh && \
    tr -d '\r' < /workspace/setup.sh > /workspace/setup.sh.tmp && \
    mv /workspace/setup.sh.tmp /workspace/setup.sh && \
    chmod +x /workspace/*.sh

# Create required directories
RUN mkdir -p /workspace/ComfyUI/models/{unet,text_encoders,vae,upscale,loras} && \
    mkdir -p /workspace/logs

# Remove any problematic extensions
RUN rm -rf /workspace/ComfyUI/web/extensions/EG_GN_NODES || true

WORKDIR /workspace

ENTRYPOINT ["/workspace/start.sh"]