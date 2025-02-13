# Use RunPod pytorch base image which includes JupyterLab
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

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

# Update pip and install Python dependencies
RUN pip install --upgrade --no-cache-dir pip && \
    pip install --upgrade setuptools wheel && \
    pip install numpy==1.23.5 && \
    pip install --no-cache-dir triton sageattention

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Clone ComfyUI and install core dependencies
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    pip install -r requirements.txt

# Install core custom nodes
RUN cd /workspace/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/chengzeyi/Comfy-WaveSpeed.git && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui && \
    for d in */ ; do \
        if [ -f "${d}requirements.txt" ]; then \
            cd "$d" && pip install -r requirements.txt || true && cd ..; \
        fi \
    done

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
if [ ! -d "ComfyUI" ]; then
    /install-repositories.sh
fi

# Create model directories if they dont exist
mkdir -p /workspace/ComfyUI/models/{unet,text_encoders,vae,clip_vision,loras}

# Download UNET model
if [ ! -f /workspace/ComfyUI/models/unet/hunyuan_video_720_cfgdistill_bf16.safetensors ]; then
    echo "Downloading hunyuan_video_720_cfgdistill_bf16.safetensors..."
    wget -O /workspace/ComfyUI/models/unet/hunyuan_video_720_cfgdistill_bf16.safetensors \
        "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors"
fi

# Download text encoder models
if [ ! -f /workspace/ComfyUI/models/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors ]; then
    echo "Downloading Long-ViT-L-14-GmP-SAE-TE-only.safetensors..."
    wget -O /workspace/ComfyUI/models/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors \
        "https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"
fi

if [ ! -f /workspace/ComfyUI/models/text_encoders/llava_llama3_fp8_scaled.safetensors ]; then
    echo "Downloading llava_llama3_fp8_scaled.safetensors..."
    wget -O /workspace/ComfyUI/models/text_encoders/llava_llama3_fp8_scaled.safetensors \
        "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors"
fi

# Download VAE model
if [ ! -f /workspace/ComfyUI/models/vae/hunyuan_video_vae_bf16.safetensors ]; then
    echo "Downloading hunyuan_video_vae_bf16.safetensors..."
    wget -O /workspace/ComfyUI/models/vae/hunyuan_video_vae_bf16.safetensors \
        "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors"
fi

# Download CLIP vision model
if [ ! -f /workspace/ComfyUI/models/clip_vision/clip-vit-large-patch14.safetensors ]; then
    echo "Downloading clip-vit-large-patch14.safetensors..."
    wget -O /workspace/ComfyUI/models/clip_vision/clip-vit-large-patch14.safetensors \
        "https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors"
fi

# Download FastVideo LoRA model
if [ ! -f /workspace/ComfyUI/models/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors ]; then
    echo "Downloading hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors..."
    wget -O /workspace/ComfyUI/models/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors \
        "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"
fi

# Start ComfyUI in the background
cd /workspace/ComfyUI
nohup python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /workspace/comfyui.log 2>&1 &

# Start VS Code in the background with no auth
nohup code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/vscode.log 2>&1 &
EOT

RUN chmod +x /pre_start.sh

# Expose ports for VS Code Web and ComfyUI
EXPOSE 8080 8188 8888

# Use RunPod's default start script
CMD ["/start.sh"]