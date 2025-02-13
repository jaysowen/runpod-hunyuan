# Use RunPod pytorch base image which includes JupyterLab
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Update pip and install Python dependencies
RUN pip install --upgrade --no-cache-dir pip && \
    pip install --upgrade setuptools wheel && \
    pip install numpy && \
    pip install --no-cache-dir triton sageattention

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

RUN mkdir -p /workspace

# Create workspace directory
WORKDIR /workspace
# Clone and set up ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git


COPY download-fix.sh /download-fix.sh
COPY AllinOneUltra1.2.json /ComfyUI/user/default/workflows/AllinOneUltra1.2.json
COPY AllinOneUltra1.3.json /ComfyUI/user/default/workflows/AllinOneUltra1.3.json

WORKDIR /workspace/ComfyUI
# Install ComfyUI requirements
RUN pip install -r requirements.txt
RUN pip install moviepy opencv-python pillow


WORKDIR /workspace/ComfyUI

# Install custom nodes
RUN mkdir -p custom_nodes && \
    cd custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/chengzeyi/Comfy-WaveSpeed.git && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui
    

# Install custom nodes requirements
RUN cd custom_nodes/ComfyUI-Manager && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Easy-Use && pip install -r requirements.txt || true  && \
    cd ../ComfyUI-Crystools && pip install -r requirements.txt || true && \
    cd ../ComfyUI-KJNodes && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Impact-Pack && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Custom-Scripts && pip install -r requirements.txt || true && \
    cd ../rgthree-comfy && pip install -r requirements.txt || true && \
    cd ../Comfy-WaveSpeed && pip install -r requirements.txt || true && \
    cd ../was-node-suite-comfyui && pip install -r requirements.txt || true


WORKDIR /

# Copy workflow file and installation scripts
COPY install-repositories.sh /install-repositories.sh
RUN chmod +x /install-repositories.sh

# Rest of the Dockerfile remains the same...
COPY <<-'EOT' /pre_start.sh
#!/bin/bash

cd /workspace
if [ ! -d "ComfyUI" ]; then
    /install-repositories.sh
fi
EOT

RUN chmod +x /pre_start.sh

# Expose ports for VS Code Web and ComfyUI
EXPOSE 8080 8188 8888

# Use RunPod's default start script
CMD ["/start.sh"]