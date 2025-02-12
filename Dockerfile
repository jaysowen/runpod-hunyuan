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

# Set up workspace and ensure persistence
WORKDIR /workspace

# Clone ComfyUI base
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install -r requirements.txt

# Clone core custom nodes
RUN cd ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/BlenderNeko/ComfyUI_Noise.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/Kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git

# Configure code-server
RUN mkdir -p /root/.config/code-server && \
    echo "bind-addr: 0.0.0.0:8080\nauth: password\npassword: runpod\ncert: false" > /root/.config/code-server/config.yaml

# Expose port for VS Code Web
EXPOSE 8080

# Use RunPod's default start script
CMD ["/start.sh"]