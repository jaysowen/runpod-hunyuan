FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    git \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    wget \
    openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Create symlinks for Python
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/python3.10 /usr/bin/python3

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install Python packages
RUN pip3 install --no-cache-dir \
    jupyterlab \
    jupyterlab_widgets \
    ipykernel \
    ipywidgets \
    aiohttp && \
    pip3 install --no-cache-dir \
    torch==2.2.1 \
    torchvision \
    torchaudio \
    --extra-index-url https://download.pytorch.org/whl/cu124

# Clone ComfyUI to root directory
WORKDIR /
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install --no-cache-dir -r requirements.txt


WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    if [ -f ComfyUI-Manager/requirements.txt ]; then pip install -r ComfyUI-Manager/requirements.txt; fi && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    if [ -f ComfyUI-Easy-Use/requirements.txt ]; then pip install -r ComfyUI-Easy-Use/requirements.txt; fi && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git && \
    if [ -f ComfyUI-Crystools/requirements.txt ]; then pip install -r ComfyUI-Crystools/requirements.txt; fi && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    if [ -f ComfyUI-KJNodes/requirements.txt ]; then pip install -r ComfyUI-KJNodes/requirements.txt; fi && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    if [ -f ComfyUI-Impact-Pack/requirements.txt ]; then pip install -r ComfyUI-Impact-Pack/requirements.txt; fi && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    if [ -f ComfyUI-Custom-Scripts/requirements.txt ]; then pip install -r ComfyUI-Custom-Scripts/requirements.txt; fi && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    if [ -f rgthree-comfy/requirements.txt ]; then pip install -r rgthree-comfy/requirements.txt; fi && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui && \
    if [ -f was-node-suite-comfyui/requirements.txt ]; then pip install -r was-node-suite-comfyui/requirements.txt; fi

# Copy workflow file and installation scripts
COPY AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/AllinOneUltra1.2.json
COPY AllinOneUltra1.3.json /workspace/ComfyUI/user/default/workflows/AllinOneUltra1.3.json

# Copy all scripts
COPY scripts/start.sh /start.sh
COPY scripts/pre_start.sh /pre_start.sh
COPY scripts/download_models.sh /download_models.sh
COPY scripts/install_nodes.sh /install_nodes.sh


# Make scripts executable
RUN chmod +x /*.sh

# Create workspace and logs directory
RUN mkdir -p /workspace/logs

CMD ["/start.sh"]