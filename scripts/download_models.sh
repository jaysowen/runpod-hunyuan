#!/bin/bash
set -e

MODEL_DIR=/workspace/ComfyUI/models"
mkdir -p ${MODEL_DIR}/{checkpoints,text_encoder,clip_vision,vae}

download_if_not_exists() {
    local url=$1
    local dest=$2
    local filename=$(basename "$dest")
    
    if [ ! -f "$dest" ]; then
        echo "Downloading $filename..."
        wget -q --show-progress "$url" -O "$dest"
        echo "Downloaded $filename successfully"
    else
        echo "$filename already exists, skipping download"
    fi
}

# Download models
# download_if_not_exists "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors" \
#     "${MODEL_DIR}/checkpoints/hunyuan_video_720_cfgdistill_bf16.safetensors"

# download_if_not_exists "https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors" \
#     "${MODEL_DIR}/text_encoder/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"

# download_if_not_exists "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors" \
#     "${MODEL_DIR}/text_encoder/llava_llama3_fp8_scaled.safetensors"

download_if_not_exists "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors" \
    "${MODEL_DIR}/vae/hunyuan_video_vae_bf16.safetensors"

# download_if_not_exists "https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors" \
#     "${MODEL_DIR}/clip_vision/model.safetensors"

# download_if_not_exists "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors" \
#     "${MODEL_DIR}/checkpoints/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"

echo "All models downloaded successfully"