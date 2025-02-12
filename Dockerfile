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

# Create service files for runpod
RUN mkdir -p /etc/supervisor/conf.d/

# Create ComfyUI service file
RUN echo '[program:comfyui]\n\
command=python /workspace/ComfyUI/main.py --listen 0.0.0.0 --port 8188 --enable-cors-header\n\
directory=/workspace/ComfyUI\n\
autostart=true\n\
autorestart=true\n\
stdout_logfile=/workspace/logs/comfyui.log\n\
stderr_logfile=/workspace/logs/comfyui.err\n\
environment=PYTHONUNBUFFERED=1\n\
' > /etc/supervisor/conf.d/comfyui.conf

# Create VS Code service file
RUN echo '[program:code-server]\n\
command=code-server --bind-addr 0.0.0.0:8080 --auth none\n\
directory=/workspace\n\
autostart=true\n\
autorestart=true\n\
stdout_logfile=/workspace/logs/vscode.log\n\
stderr_logfile=/workspace/logs/vscode.err\n\
' > /etc/supervisor/conf.d/code-server.conf

# Create download fix script
RUN echo '#!/bin/bash\n\
\n\
MODEL_BASE_DIR="/workspace/ComfyUI/models"\n\
\n\
verify_and_redownload() {\n\
    local file_path="$1"\n\
    local url="$2"\n\
    local min_size=$((20 * 1024 * 1024))\n\
    \n\
    if [ -f "$file_path" ]; then\n\
        local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path")\n\
        if [ "$file_size" -lt "$min_size" ]; then\n\
            rm "$file_path"\n\
            wget -O "$file_path" "$url"\n\
        fi\n\
    else\n\
        wget -O "$file_path" "$url"\n\
    fi\n\
}\n\
\n\
declare -A MODEL_URLS=(\n\
    ["${MODEL_BASE_DIR}/unet/hunyuan_video_720_cfgdistill_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors"\n\
    ["${MODEL_BASE_DIR}/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"]="https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"\n\
    ["${MODEL_BASE_DIR}/text_encoders/llava_llama3_fp8_scaled.safetensors"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors"\n\
    ["${MODEL_BASE_DIR}/vae/hunyuan_video_vae_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors"\n\
    ["${MODEL_BASE_DIR}/clip_vision/clip-vit-large-patch14.safetensors"]="https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors"\n\
)\n\
\n\
for file_path in "${!MODEL_URLS[@]}"; do\n\
    verify_and_redownload "$file_path" "${MODEL_URLS[$file_path]}"\n\
done\n\
' > /workspace/download-fix.sh && chmod +x /workspace/download-fix.sh

# Verify the installation
RUN ls -la /workspace && \
    ls -la /workspace/ComfyUI && \
    python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

WORKDIR /workspace