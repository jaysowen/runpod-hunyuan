# Build stage
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04 as builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Combine all ARGs
ARG PYTHON_VERSION=3.12.1
ARG TORCH_VERSION=2.2.1
ARG CUDA_VERSION=cu124
ARG COMFYUI_VERSION=latest

# Install essential packages in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    git wget curl \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /venv

# Set environment for builder
ENV PATH="/venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

# Install Python packages in a single layer
RUN pip install --no-cache-dir -U pip setuptools wheel && \
    pip install --no-cache-dir torch==${TORCH_VERSION} torchvision torchaudio \
    --extra-index-url https://download.pytorch.org/whl/${CUDA_VERSION} && \
    pip install --no-cache-dir jupyterlab jupyterlab_widgets ipykernel ipywidgets

# Install ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    git checkout tags/${COMFYUI_VERSION} && \
    pip install --no-cache-dir -r requirements.txt

# Install core custom nodes
RUN cd ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git

# Install requirements for core nodes
RUN cd ComfyUI/custom_nodes && \
    find . -name "requirements.txt" -exec pip install --no-cache-dir -r {} \;

# Run install scripts for core nodes if they exist
RUN cd ComfyUI/custom_nodes && \
    for script in */install.py; do \
        if [ -f "$script" ]; then \
            python "$script"; \
        fi \
    done

# Runtime stage
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 nginx-light rsync openssh-server ffmpeg libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Set runtime environment variables
ENV PYTHONUNBUFFERED=True
ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu

# Create necessary directories
RUN mkdir -p /comfy-models/{checkpoints,text_encoder,clip_vision,vae} \
    /workspace/ComfyUI /workspace/logs

# Copy from builder
COPY --from=builder /venv /venv
COPY --from=builder /ComfyUI /ComfyUI

# Copy configuration and scripts
COPY proxy/nginx.conf /etc/nginx/nginx.conf
COPY proxy/readme.html /usr/share/nginx/html/readme.html
COPY scripts/start.sh scripts/pre_start.sh scripts/install_nodes.sh scripts/download_models.sh /
RUN chmod +x /start.sh /pre_start.sh /install_nodes.sh /download_models.sh

# Welcome message
COPY logo/runpod.txt /etc/runpod.txt
RUN echo 'cat /etc/runpod.txt' >> /root/.bashrc && \
    echo 'echo -e "\nFor detailed documentation and guides, please visit:\n\033[1;34mhttps://docs.runpod.io/\033[0m and \033[1;34mhttps://blog.runpod.io/\033[0m\n\n"' >> /root/.bashrc

CMD ["/start.sh"]