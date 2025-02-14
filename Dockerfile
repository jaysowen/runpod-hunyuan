FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    wget \
    curl \
    libgl1-mesa-glx \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \
    torch \
    torchvision \
    torchaudio \
    opencv-python \
    numpy \
    pillow \
    requests \
    tqdm

# Clone ComfyUI repository
WORKDIR /workspace
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# Install ComfyUI dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Create necessary directories
RUN mkdir -p /workspace/ComfyUI/models/checkpoints
RUN mkdir -p /workspace/ComfyUI/models/vae
RUN mkdir -p /workspace/ComfyUI/models/loras
RUN mkdir -p /workspace/ComfyUI/models/controlnet
RUN mkdir -p /workspace/ComfyUI/input
RUN mkdir -p /workspace/ComfyUI/output



# Rest of the Dockerfile remains the same...
COPY <<-'EOT' /pre_start.sh
#!/bin/bash
cd /workspace
if [ -d "ComfyUI" ]; then
    /install-repositories.sh
fi

# Start ComfyUI in the background
cd /workspace/ComfyUI
nohup python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /workspace/comfyui.log 2>&1 &

# Start VS Code in the background with no auth
nohup code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/vscode.log 2>&1 &
EOT

RUN chmod +x /pre_start.sh

# Expose ports
EXPOSE 8080 8188 8888

# Set up entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/start.sh"]