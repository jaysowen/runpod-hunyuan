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
    npm && \
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

# Install custom nodes (original + new correct list)
RUN mkdir -p custom_nodes && \
    cd custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/BlenderNeko/ComfyUI_Noise.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/chrisgoringe/cg-noisetools.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/7eu7d7/ComfyUI-HuggingFace-Nodes.git && \
    git clone https://github.com/thecooltechguy/ComfyUI-Essentials.git && \
    git clone https://github.com/LucianoCirino/efficiency-nodes-comfyui.git && \
    git clone https://github.com/MECv2/ComfyUI-Advanced-ControlNet.git && \
    git clone https://github.com/Rayzr522/ComfyUI-Flux.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/cubiq/ComfyUI_essentials.git && \
    git clone https://github.com/chrisgoringe/cg-use-everywhere.git && \
    git clone https://github.com/Jonseed/ComfyUI-Detail-Daemon.git && \
    git clone https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git && \
    git clone https://github.com/Amorano/Jovimetrix.git && \
    git clone https://github.com/sipherxyz/comfyui-art-venture.git && \
    git clone https://github.com/theUpsider/ComfyUI-Logic.git && \
    git clone https://github.com/Smirnov75/ComfyUI-mxToolkit.git && \
    git clone https://github.com/alt-key-project/comfyui-dream-project.git && \
    git clone https://github.com/pharmapsychotic/comfy-cliption.git && \
    git clone https://github.com/darkpixel/darkprompts.git && \
    git clone https://github.com/Koushakur/ComfyUI-DenoiseChooser.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git && \
    git clone https://github.com/giriss/comfy-image-saver.git && \
    git clone https://github.com/facok/ComfyUI-HunyuanVideoMultiLora.git && \
    git clone https://github.com/11dogzi/Comfyui-ergouzi-Nodes.git && \
    git clone https://github.com/jamesWalker55/comfyui-various.git && \
    git clone https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git && \
    git clone https://github.com/ShmuelRonen/ComfyUI-ImageMotionGuider.git && \
    git clone https://github.com/M1kep/ComfyLiterals.git

# Install custom nodes requirements
RUN cd custom_nodes/ComfyUI-Manager && pip install -r requirements.txt || true && \
    cd ../ComfyUI-VideoHelperSuite && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Frame-Interpolation && pip install -r requirements.txt || true && \
    cd ../ComfyUI_Noise && pip install -r requirements.txt || true && \
    cd ../cg-noisetools && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Crystools && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Impact-Pack && pip install -r requirements.txt || true && \
    cd ../rgthree-comfy && pip install -r requirements.txt || true && \
    cd ../ComfyUI-KJNodes && pip install -r requirements.txt || true && \
    cd ../ComfyUI-HuggingFace-Nodes && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Easy-Use && pip install -r requirements.txt || true && \
    cd ../ComfyUI_essentials && pip install -r requirements.txt || true && \
    cd ../cg-use-everywhere && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Detail-Daemon && pip install -r requirements.txt || true && \
    cd ../Comfyui_TTP_Toolset && pip install -r requirements.txt || true && \
    cd ../Jovimetrix && pip install -r requirements.txt || true && \
    cd ../comfyui-art-venture && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Logic && pip install -r requirements.txt || true && \
    cd ../ComfyUI-mxToolkit && pip install -r requirements.txt || true && \
    cd ../comfyui-dream-project && pip install -r requirements.txt || true && \
    cd ../comfy-cliption && pip install -r requirements.txt || true && \
    cd ../darkprompts && pip install -r requirements.txt || true && \
    cd ../ComfyUI-DenoiseChooser && pip install -r requirements.txt || true && \
    cd ../ComfyUI-GGUF && pip install -r requirements.txt || true && \
    cd ../comfy-image-saver && pip install -r requirements.txt || true && \
    cd ../ComfyUI-HunyuanVideoMultiLora && pip install -r requirements.txt || true && \
    cd ../Comfyui-ergouzi-Nodes && pip install -r requirements.txt || true && \
    cd ../comfyui-various && pip install -r requirements.txt || true && \
    cd ../ComfyUI_JPS-Nodes && pip install -r requirements.txt || true && \
    cd ../ComfyUI-ImageMotionGuider && pip install -r requirements.txt || true && \
    cd ../ComfyLiterals && pip install -r requirements.txt || true
    
# Create model directories
RUN mkdir -p models/{diffusion_models,text_encoders,vae,upscale,loras}

# Copy startup scripts
COPY setup.sh /workspace/setup.sh
COPY start.sh /workspace/start.sh

# Make scripts executable
RUN chmod +x /workspace/setup.sh /workspace/start.sh

# Expose ports
EXPOSE 8080 8188

WORKDIR /workspace

ENTRYPOINT ["/workspace/start.sh"]