FROM nvidia/cuda:11.8.0-base-ubuntu22.04 as runtime

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set environment variables
ENV SHELL=/bin/bash
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /

# System setup and dependencies
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
    ffmpeg \
    nodejs \
    npm && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt install python3.10-dev python3.10-venv -y --no-install-recommends && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Set up Python
RUN ln -s /usr/bin/python3.10 /usr/bin/python && \
    rm /usr/bin/python3 && \
    ln -s /usr/bin/python3.10 /usr/bin/python3 && \
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python get-pip.py

# Create and activate virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python packages
RUN pip install --upgrade --no-cache-dir pip && \
    pip install --upgrade setuptools && \
    pip install --upgrade wheel

# Install PyTorch with CUDA 11.8 support
RUN pip install --upgrade --no-cache-dir \
    torch==2.0.1+cu118 \
    torchvision==0.15.2+cu118 \
    torchaudio==2.0.2 \
    --index-url https://download.pytorch.org/whl/cu118

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Create workspace directory
WORKDIR /workspace

# Clone and set up ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# Install ComfyUI requirements
RUN pip install -r requirements.txt
RUN pip install moviepy opencv-python pillow

# Install custom nodes including ComfyUI-Manager and cg-noisetools
RUN mkdir -p custom_nodes && \
    cd custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone https://github.com/BlenderNeko/ComfyUI_Noise.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/chrisgoringe/cg-noisetools.git

# Install custom nodes requirements
RUN cd custom_nodes/ComfyUI-Manager && pip install -r requirements.txt || true && \
    cd ../ComfyUI-VideoHelperSuite && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Frame-Interpolation && pip install -r requirements.txt || true && \
    cd ../ComfyUI_Noise && pip install -r requirements.txt || true && \
    cd ../cg-noisetools && pip install -r requirements.txt || true

# Create model directories
RUN mkdir -p models/{diffusion_models,text_encoders,vae,upscale,loras/HUNYUAN/custom}

# Download model files
RUN wget -O models/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensors \
    "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensors?download=true" && \
    wget -O models/text_encoders/clip_l.safetensors \
    "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/clip_l.safetensors?download=true" && \
    wget -O models/text_encoders/llava_llama3_fp8_scaled.safetensors \
    "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors?download=true" && \
    wget -O models/vae/hunyuan_video_vae_bf16.safetensors \
    "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/vae/hunyuan_video_vae_bf16.safetensors?download=true"

# Download upscale model
RUN cd models/upscale && \
    wget -O 4x_foolhardy_Remacri.pth \
    "https://huggingface.co/datasets/FacehugmansPics/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth"

# Copy startup scripts
COPY setup.sh /workspace/setup.sh
COPY start.sh /workspace/start.sh

# Make scripts executable
RUN chmod +x /workspace/setup.sh /workspace/start.sh

# Run setup
RUN /workspace/setup.sh

# Expose ports
EXPOSE 8080 8188

WORKDIR /workspace

ENTRYPOINT ["/workspace/start.sh"]