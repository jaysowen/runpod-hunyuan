# Use RunPod pytorch base image which includes JupyterLab
FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel-ubuntu22.04

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

# Copy workflow file and installation scripts
COPY AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/AllinOneUltra1.2.json
COPY AllinOneUltra1.3.json /workspace/ComfyUI/user/default/workflows/AllinOneUltra1.3.json
COPY download-fix.sh /workspace/download-fix.sh
COPY install-repositories.sh /install-repositories.sh
RUN chmod +x /install-repositories.sh

# Create and set up the pre-start script
COPY <<-'EOT' /pre_start.sh
#!/bin/bash
cd /workspace
if [ ! -d "ComfyUI" ]; then
    /install-repositories.sh
fi

# Create model directories if they don't exist
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
EXPOSE 8080 8188

# Use RunPod's default start script
CMD ["/start.sh"]