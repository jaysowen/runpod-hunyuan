# Use RunPod pytorch base image which includes JupyterLab
FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel-ubuntu22.04

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
    pip install numpy==1.23.5 && \
    pip install --no-cache-dir triton sageattention

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Copy workflow file and installation scripts
COPY AllinOneUltra1.2.json /AllinOneUltra1.2.json
COPY AllinOneUltra1.3.json /AllinOneUltra1.3.json
COPY install-repositories.sh /install-repositories.sh
RUN chmod +x /install-repositories.sh

# Create and set up the pre-start script
COPY <<-'EOT' /pre_start.sh
#!/bin/bash
cd /workspace
if [ ! -d "ComfyUI" ]; then
    /install-repositories.sh
    
    # Create workflows directory and copy the workflow file
    cp /AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/
    cp /AllinOneUltra1.3.json /workspace/ComfyUI/user/default/workflows/
fi

# Start ComfyUI in the background
cd /workspace/ComfyUI
nohup python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /workspace/comfyui.log 2>&1 &

# Start VS Code in the background
nohup code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/vscode.log 2>&1 &
EOT

RUN chmod +x /pre_start.sh

# Configure code-server
RUN mkdir -p /root/.config/code-server && \
    echo "bind-addr: 0.0.0.0:8080\nauth: password\npassword: runpod\ncert: false" > /root/.config/code-server/config.yaml

# Expose ports for VS Code Web and ComfyUI
EXPOSE 8080 8188

# Use RunPod's default start script
CMD ["/start.sh"]