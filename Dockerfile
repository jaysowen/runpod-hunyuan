FROM nvidia/cuda:11.8.0-base-ubuntu22.04 as runtime

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set environment variables
ENV SHELL=/bin/bash
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /

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
    dos2unix && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt install python3.10-dev python3.10-venv -y --no-install-recommends && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Set up Python
RUN ln -s /usr/bin/python3.10 /usr/bin/python && \
    rm /usr/bin/python3 && \
    ln -s /usr/bin/python3.10 /usr/bin/python3 && \
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python get-pip.py

# Create and activate virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python packages
RUN pip install --upgrade --no-cache-dir pip && \
    pip install --upgrade setuptools && \
    pip install --upgrade wheel

# Install numpy first with specific version
RUN pip install numpy==1.23.5

# Install latest PyTorch with CUDA 11.8 support
RUN pip install --no-cache-dir \
    torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu118

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
    git clone https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git

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
    git clone https://github.com/WASasquatch/was-node-suite-comfyui

# Install requirements for all custom nodes
WORKDIR /workspace/ComfyUI
RUN find custom_nodes -name requirements.txt -exec pip install -r {} \;

# Create model directories
RUN mkdir -p models/{unet,text_encoders,vae,upscale,loras}

# Create workflows directory
RUN mkdir -p /workspace/ComfyUI/user/default/workflows

# Copy workflow file
COPY AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/

# Copy startup scripts
COPY start.sh /workspace/start.sh
COPY setup.sh /workspace/setup.sh
COPY download-fix.sh /workspace//download-fix.sh

# Fix line endings and set permissions - using tr instead of dos2unix
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