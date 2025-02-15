# Set the base image
ARG BASE_IMAGE=nvidia/cuda:12.4.0-devel-ubuntu22.04
FROM ${BASE_IMAGE}

# Set the shell and enable pipefail for better error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set basic environment variables
ARG COMFYUI_VERSION
ARG PYTHON_VERSION
ARG TORCH_VERSION
ARG CUDA_VERSION

# Set basic environment variables
ENV SHELL=/bin/bash 
ENV PYTHONUNBUFFERED=True 
ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu 
ENV UV_COMPILE_BYTECODE=1

# Shared python package cache
ENV PIP_CACHE_DIR="/runpod-volume/.cache/pip/"
ENV UV_CACHE_DIR="/runpod-volume/.cache/uv/"

# Set working directory
WORKDIR /

# Install essential packages (optimized to run in one command)
RUN apt-get update --yes && \
    apt-get upgrade --yes && \
    apt-get install --yes --no-install-recommends \
        git wget curl bash nginx-light rsync sudo binutils ffmpeg \ 
        build-essential \
        libgl1 libglib2.0-0 \
        openssh-server ca-certificates && \
    apt-get autoremove -y && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install the UV tool from astral-sh
ADD https://astral.sh/uv/install.sh /uv-installer.sh
RUN sh /uv-installer.sh && rm /uv-installer.sh
ENV PATH="/root/.local/bin/:$PATH"

# Install Python and create virtual environment
RUN uv python install ${PYTHON_VERSION} --default --preview && \
    uv venv --seed /workspace/venv
ENV PATH="/workspace/venv/bin:$PATH"

# Install essential Python packages and dependencies
RUN pip install --no-cache-dir -U \
    pip setuptools wheel \
    jupyterlab jupyterlab_widgets ipykernel ipywidgets \
    torch==${TORCH_VERSION} \
    torchvision \
    torchaudio \
    --extra-index-url https://download.pytorch.org/whl/${CUDA_VERSION}

# Install ComfyUI and ComfyUI Manager
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    git checkout tags/${COMFYUI_VERSION} && \
    pip install --no-cache-dir -r requirements.txt

# Clone custom nodes repositories
RUN cd ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git

# Install requirements for all nodes
RUN cd ComfyUI/custom_nodes && \
    find . -name "requirements.txt" -exec pip install --no-cache-dir -r {} \;

# Run install scripts if they exist
RUN cd ComfyUI/custom_nodes && \
    for script in */install.py; do \
        if [ -f "$script" ]; then \
            python "$script"; \
        fi \
    done

# Create model directories
RUN mkdir -p /comfy-models/checkpoints /comfy-models/text_encoder /comfy-models/clip_vision /comfy-models/vae /workspace/ComfyUI /workspace/logs

RUN mv /workspace/venv /

# NGINX Proxy Configuration
COPY proxy/nginx.conf /etc/nginx/nginx.conf
COPY proxy/readme.html /usr/share/nginx/html/readme.html

# Copy scripts
COPY scripts/start.sh /
COPY scripts/pre_start.sh /
COPY scripts/download_models.sh /
COPY scripts/install_node.sh /
RUN chmod +x /start.sh /pre_start.sh /download_models.sh /install_node.sh

# Welcome Message
COPY logo/runpod.txt /etc/runpod.txt
RUN echo 'cat /etc/runpod.txt' >> /root/.bashrc
RUN echo 'echo -e "\nFor detailed documentation and guides, please visit:\n\033[1;34mhttps://docs.runpod.io/\033[0m and \033[1;34mhttps://blog.runpod.io/\033[0m\n\n"' >> /root/.bashrc

CMD ["/start.sh"]