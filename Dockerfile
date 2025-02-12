FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=/bin/bash

# System setup and dependencies
RUN apt-get update --yes && \
    apt-get upgrade --yes && \
    apt install --yes --no-install-recommends \
    git \
    wget \
    curl \
    libgl1 \
    ffmpeg \
    rsync \
    openssh-server \
    nginx \
    software-properties-common && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Create workspace directory
WORKDIR /workspace

# Clone and set up ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# Install ComfyUI requirements
RUN pip install -r requirements.txt && \
    pip install moviepy opencv-python pillow xformers

# Create and organize directories
RUN mkdir -p custom_nodes && \
    mkdir -p models/{unet,text_encoders,vae,upscale,loras,clip_vision} && \
    mkdir -p /workspace/ComfyUI/user/default/workflows && \
    mkdir -p /workspace/logs

# Install core custom nodes
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/BlenderNeko/ComfyUI_Noise.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git

# Install requirements for custom nodes
WORKDIR /workspace/ComfyUI
RUN find custom_nodes -name requirements.txt -exec pip install -r {} \;

# Copy scripts
COPY pre_start.sh /pre_start.sh
COPY start.sh /start.sh
COPY download-fix.sh /workspace/download-fix.sh

# Fix line endings and set permissions
RUN chmod +x /pre_start.sh /start.sh /workspace/download-fix.sh && \
    dos2unix /pre_start.sh /start.sh /workspace/download-fix.sh

WORKDIR /workspace

ENTRYPOINT ["/start.sh"]