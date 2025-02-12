FROM nvidia/cuda:12.4.0-base-ubuntu22.04 as runtime
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set working directory and environment variables
ENV SHELL=/bin/bash
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /

# Set up system
RUN apt-get update --yes && \
    apt-get upgrade --yes && \
    apt install --yes --no-install-recommends \
    git \
    wget \
    curl \
    bash \
    libgl1 \
    software-properties-common \
    openssh-server \
    nginx \
    rsync \
    ffmpeg \
    dos2unix && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt install python3.10-dev python3.10-venv -y --no-install-recommends && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Set up Python and pip
RUN ln -s /usr/bin/python3.10 /usr/bin/python && \
    rm /usr/bin/python3 && \
    ln -s /usr/bin/python3.10 /usr/bin/python3 && \
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python get-pip.py

# Set up virtual environment
RUN python -m venv /venv
ENV PATH="/venv/bin:$PATH"

# Install necessary Python packages
RUN pip install --upgrade --no-cache-dir pip && \
    pip install --upgrade setuptools && \
    pip install --upgrade wheel

# Install PyTorch with CUDA 12.4 support
RUN pip install --upgrade --no-cache-dir \
    torch \
    torchvision \
    torchaudio \
    --index-url https://download.pytorch.org/whl/cu121

# Install additional Python packages
RUN pip install --upgrade --no-cache-dir \
    jupyterlab \
    ipywidgets \
    jupyter-archive \
    jupyter_contrib_nbextensions \
    triton \
    xformers \
    notebook==6.5.5 \
    moviepy \
    opencv-python \
    pillow

# Set up Jupyter
RUN jupyter contrib nbextension install --user && \
    jupyter nbextension enable --py widgetsnbextension

# Install ComfyUI and custom nodes
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd /ComfyUI && \
    pip install -r requirements.txt

# Install ComfyUI Manager and other nodes
WORKDIR /ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/BlenderNeko/ComfyUI_Noise.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git

# Install custom node requirements
WORKDIR /ComfyUI
RUN find custom_nodes -name requirements.txt -exec pip install -r {} \;

# Create necessary directories
RUN mkdir -p /workspace && \
    mkdir -p /comfy-models && \
    mkdir -p /root/.cache/huggingface && \
    mkdir -p /ComfyUI/models/{unet,text_encoders,vae,upscale,loras,clip_vision}

# Download our specific models
RUN cd /ComfyUI/models && \
    wget -O unet/hunyuan_video_720_cfgdistill_bf16.safetensors \
    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors" && \
    wget -O text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors \
    "https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors" && \
    wget -O text_encoders/llava_llama3_fp8_scaled.safetensors \
    "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors" && \
    wget -O vae/hunyuan_video_vae_bf16.safetensors \
    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors" && \
    wget -O clip_vision/clip-vit-large-patch14.safetensors \
    "https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors"

# Copy scripts and configurations
COPY pre_start.sh /pre_start.sh
COPY start.sh /start.sh
COPY download-fix.sh /workspace/download-fix.sh

# Fix line endings and set permissions
RUN chmod +x /pre_start.sh /start.sh /workspace/download-fix.sh && \
    dos2unix /pre_start.sh /start.sh /workspace/download-fix.sh

# Set working directory and entrypoint
WORKDIR /workspace
ENTRYPOINT ["/start.sh"]