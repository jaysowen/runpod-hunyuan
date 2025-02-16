#!/bin/bash
set -e

MODEL_DIR="/workspace/ComfyUI/models"
mkdir -p ${MODEL_DIR}/{checkpoints,text_encoder,clip_vision,vae}

download_if_not_exists() {
    local url=$1
    local dest=$2
    local filename=$(basename "$dest")
    
    if [ ! -f "$dest" ]; then
        echo "DOWNLOADING --  $filename..."
        wget -q --show-progress "$url" -O "$dest"
        echo "COMPLETED $filename successfully"
    else
        echo "$filename already exists, skipping download"
    fi
}

# Download models
download_if_not_exists "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensors" \
    "${MODEL_DIR}/unet/hunyuan_video_t2v_720p_bf16.safetensors"

download_if_not_exists "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/clip_l.safetensors" \
    "${MODEL_DIR}/text_encoder/clip_l.safetensors"

download_if_not_exists "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors" \
    "${MODEL_DIR}/text_encoder/llava_llama3_fp8_scaled.safetensors"

download_if_not_exists "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/vae/hunyuan_video_vae_bf16.safetensor" \
    "${MODEL_DIR}/vae/hunyuan_video_vae_bf16.safetensors"

/install_nodes.sh

echo "All models downloaded successfully"