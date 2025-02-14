FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    wget \
    curl \
    libgl1-mesa-glx \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \
    # torch \
    # torchvision \
    # torchaudio \
    opencv-python \
    numpy \
    pillow \
    requests \
    tqdm

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Clone ComfyUI repository
WORKDIR /workspace
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# Install ComfyUI dependencies
WORKDIR /workspace/ComfyUI
RUN pip install --no-cache-dir -r requirements.txt

# Create necessary directories
RUN mkdir -p /workspace/ComfyUI/models/checkpoints
RUN mkdir -p /workspace/ComfyUI/models/vae
RUN mkdir -p /workspace/ComfyUI/models/loras
RUN mkdir -p /workspace/ComfyUI/models/controlnet
RUN mkdir -p /workspace/ComfyUI/input
RUN mkdir -p /workspace/ComfyUI/output

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
    git clone https://github.com/chengzeyi/Comfy-WaveSpeed.git && \
    if [ -f Comfy-WaveSpeed/requirements.txt ]; then pip install -r Comfy-WaveSpeed/requirements.txt; fi && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui && \
    if [ -f was-node-suite-comfyui/requirements.txt ]; then pip install -r was-node-suite-comfyui/requirements.txt; fi


# Copy workflow file and installation scripts
COPY AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/AllinOneUltra1.2.json
COPY AllinOneUltra1.3.json /workspace/ComfyUI/user/default/workflows/AllinOneUltra1.3.json
COPY download-fix.sh /workspace/download-fix.sh
COPY install-repositories.sh /install-repositories.sh
RUN chmod +x /install-repositories.sh

# Rest of the Dockerfile remains the same...
COPY <<-'EOT' /pre_start.sh
#!/bin/bash
cd /workspace
if [ -d "ComfyUI" ]; then
    /install-repositories.sh
fi

# Start ComfyUI in the background
cd /workspace/ComfyUI
nohup python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /workspace/comfyui.log 2>&1 &

# Start VS Code in the background with no auth
nohup code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/vscode.log 2>&1 &
EOT

RUN chmod +x /pre_start.sh


# Create model directories and download models
WORKDIR /workspace/ComfyUI
RUN mkdir -p /workspace/ComfyUI/models/{unet,text_encoders,vae,clip_vision,loras} && \
    wget -O /workspace/ComfyUI/models/unet/hunyuan_video_720_cfgdistill_bf16.safetensors \
        "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors" && \
    wget -O /workspace/ComfyUI/models/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors \
        "https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors" && \
    wget -O /workspace/ComfyUI/models/text_encoders/llava_llama3_fp8_scaled.safetensors \
        "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors" && \
    wget -O /workspace/ComfyUI/models/vae/hunyuan_video_vae_bf16.safetensors \
        "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors" && \
    wget -O /workspace/ComfyUI/models/clip_vision/clip-vit-large-patch14.safetensors \
        "https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors" && \
    wget -O /workspace/ComfyUI/models/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors \
        "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"


# Expose ports
EXPOSE 8080 8188 8888

ENTRYPOINT ["/start.sh"]