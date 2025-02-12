# Use an official Python runtime as a parent image
FROM python:3.10-slim-bullseye

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

# Create a non-root user
RUN groupadd -r appuser && useradd -r -g appuser -m -s /sbin/nologin appuser

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

# Install Python packages
RUN pip install --no-cache-dir \
    jupyterlab \
    torch \
    torchvision \
    torchaudio

# Create and set working directory
WORKDIR /workspace
RUN chown appuser:appuser /workspace

# Switch to non-root user
USER appuser

# Clone repositories
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/BlenderNeko/ComfyUI_Noise.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/Kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git

# Configure JupyterLab
RUN jupyter lab --generate-config && \
    echo "c.ServerApp.ip = '0.0.0.0'" >> ~/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.allow_root = False" >> ~/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.open_browser = False" >> ~/.jupyter/jupyter_lab_config.py

# Configure code-server
RUN mkdir -p ~/.config/code-server && \
    echo "bind-addr: 0.0.0.0:8080\nauth: password\npassword: runpod\ncert: false" > ~/.config/code-server/config.yaml

# Expose ports
EXPOSE 8888 8080

# Create startup script
RUN echo '#!/bin/bash\njupyter lab --no-browser --allow-root --ip=0.0.0.0 --port=8888 --NotebookApp.token="" --NotebookApp.password="" & \ncode-server --bind-addr 0.0.0.0:8080 --auth none' > ~/start.sh && \
    chmod +x ~/start.sh

# Set the default command
CMD ["~/start.sh"]