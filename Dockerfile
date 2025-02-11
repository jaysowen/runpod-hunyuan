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

# ... (clone other custom nodes as in your original Dockerfile)

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