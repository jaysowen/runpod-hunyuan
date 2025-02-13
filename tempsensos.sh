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
