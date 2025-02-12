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

# Create and set workspace directory
WORKDIR /
RUN mkdir -p /workspace
WORKDIR /workspace

# Clone and set up ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install -r requirements.txt && \
    pip install moviepy opencv-python pillow

# Create custom_nodes directory and clone repositories
WORKDIR /workspace/ComfyUI/custom_nodes

# Clone essential custom nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/cubiq/ComfyUI_essentials.git && \
    git clone https://github.com/chrisgoringe/cg-use-everywhere.git && \
    git clone https://github.com/city96/ComfyUI-GGUF.git && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui

# Install requirements for all custom nodes
WORKDIR /workspace/ComfyUI
RUN find custom_nodes -name requirements.txt -exec pip install -r {} \;

# Create necessary directories
RUN mkdir -p models/{unet,text_encoders,vae,upscale,loras} && \
    mkdir -p user/default/workflows && \
    mkdir -p /workspace/logs

# Create service files for runpod
RUN mkdir -p /etc/supervisor/conf.d/

# Copy workflow file if it exists
COPY AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/ || echo "Workflow file not found, skipping..."

# Create ComfyUI service file
RUN echo '[program:comfyui]\n\
command=python /workspace/ComfyUI/main.py --listen 0.0.0.0 --port 8188 --enable-cors-header\n\
directory=/workspace/ComfyUI\n\
autostart=true\n\
autorestart=true\n\
stdout_logfile=/workspace/logs/comfyui.log\n\
stderr_logfile=/workspace/logs/comfyui.err\n\
environment=PYTHONUNBUFFERED=1\n\
' > /etc/supervisor/conf.d/comfyui.conf

# Create VS Code service file
RUN echo '[program:code-server]\n\
command=code-server --bind-addr 0.0.0.0:8080 --auth none\n\
directory=/workspace\n\
autostart=true\n\
autorestart=true\n\
stdout_logfile=/workspace/logs/vscode.log\n\
stderr_logfile=/workspace/logs/vscode.err\n\
' > /etc/supervisor/conf.d/code-server.conf

# Verify the installation
RUN ls -la /workspace && \
    ls -la /workspace/ComfyUI && \
    python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

WORKDIR /workspace

# Don't override the entrypoint - let runpod handle it
# The services will be started by supervisord