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

# Install Jupyter Lab
RUN pip install jupyterlab ipywidgets jupyter-resource-usage

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

# Set up Jupyter Lab configuration
RUN mkdir -p /root/.jupyter && \
    echo "c.ServerApp.ip = '0.0.0.0'" >> /root/.jupyter/jupyter_server_config.py && \
    echo "c.ServerApp.port = 8888" >> /root/.jupyter/jupyter_server_config.py && \
    echo "c.ServerApp.allow_origin = '*'" >> /root/.jupyter/jupyter_server_config.py && \
    echo "c.ServerApp.allow_root = True" >> /root/.jupyter/jupyter_server_config.py && \
    echo "c.ServerApp.token = ''" >> /root/.jupyter/jupyter_server_config.py && \
    echo "c.ServerApp.password = ''" >> /root/.jupyter/jupyter_server_config.py

# Copy scripts and set permissions
COPY start.sh /workspace/
COPY setup.sh /workspace/
COPY download-fix.sh /workspace/
COPY AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/

# Fix line endings and set permissions
RUN dos2unix /workspace/*.sh && \
    chmod +x /workspace/*.sh

# Remove any problematic extensions
RUN rm -rf /workspace/ComfyUI/web/extensions/EG_GN_NODES || true

# Verify the installation
RUN ls -la /workspace && \
    ls -la /workspace/ComfyUI && \
    python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

WORKDIR /workspace

ENTRYPOINT ["/workspace/start.sh"]