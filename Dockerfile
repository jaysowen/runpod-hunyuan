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

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Create and set up the pre-start script
RUN echo '#!/bin/bash\n\
cd /workspace\n\
if [ ! -d "ComfyUI" ]; then\n\
    git clone https://github.com/comfyanonymous/ComfyUI.git\n\
    cd ComfyUI\n\
    pip install -r requirements.txt\n\
    mkdir -p custom_nodes\n\
    cd custom_nodes\n\
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git\n\
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git\n\
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git\n\
    git clone https://github.com/BlenderNeko/ComfyUI_Noise.git\n\
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git\n\
    git clone https://github.com/Kijai/ComfyUI-KJNodes.git\n\
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git\n\
fi' > /pre_start.sh && chmod +x /pre_start.sh

# Configure code-server
RUN mkdir -p /root/.config/code-server && \
    echo "bind-addr: 0.0.0.0:8080\nauth: password\npassword: runpod\ncert: false" > /root/.config/code-server/config.yaml

# Expose port for VS Code Web
EXPOSE 8080

# Use RunPod's default start script
CMD ["/start.sh"]