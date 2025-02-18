#!/bin/bash
set -e

MODEL_DIR="/workspace/ComfyUI/models"
mkdir -p ${MODEL_DIR}/{unet,text_encoders,clip_vision,vae,loras}

# Maximum number of parallel downloads
MAX_PARALLEL=2
current_downloads=0

# Function to download with progress
download_file() {
    local url=$1
    local dest=$2
    local filename=$(basename "$dest")
    local temp_dest="${dest}.downloading"
    
    # Check if file exists
    if [ -f "$dest" ]; then
        if [ -s "$dest" ]; then
            echo "✅ $filename already exists and is not empty, skipping download"
            return 0
        else
            echo "🔄 $filename exists but is empty, re-downloading..."
            rm -f "$dest"
        fi
    fi

    echo "⬇️ Downloading $filename..."
    wget -q --show-progress "$url" -O "$temp_dest" || {
        echo "❌ Failed to download $filename"
        rm -f "$temp_dest"
        return 1
    }
    
    mv "$temp_dest" "$dest"
    echo "✅ Downloaded $filename successfully"
}

# Function to handle parallel downloads
download_parallel() {
    local url=$1
    local dest=$2
    
    download_file "$url" "$dest" &
    
    ((current_downloads++))
    
    if [ $current_downloads -ge $MAX_PARALLEL ]; then
        wait
        current_downloads=0
    fi
}

echo "🚀 Starting model downloads..."

# Download UNET models
echo "⭐ Processing UNET models..."
download_parallel "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors" \
    "${MODEL_DIR}/unet/hunyuan_video_720_cfgdistill_bf16.safetensors"

# Download LORAS models
echo "⭐ Processing LORAS models..."
download_parallel "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors" \
    "${MODEL_DIR}/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"

# Download Text Encoder models
echo "⭐ Processing Text Encoder models..."
download_parallel "https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors" \
    "${MODEL_DIR}/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"
download_parallel "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors" \
    "${MODEL_DIR}/text_encoders/llava_llama3_fp8_scaled.safetensors"

# Download VAE models
echo "⭐ Processing VAE models..."
download_parallel "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors" \
    "${MODEL_DIR}/vae/hunyuan_video_vae_bf16.safetensors"

# Download CLIP Vision models
echo "⭐ Processing CLIP Vision models..."
download_parallel "https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors" \
    "${MODEL_DIR}/clip_vision/clip-vit-large-patch14.safetensors"

# Wait for any remaining downloads
wait

# Final verification
echo "🔍 Verifying all downloads..."
verify_all_downloads() {
    local all_valid=true
    
    for dir in "unet" "loras" "text_encoders" "clip_vision" "vae"; do
        if [ -d "${MODEL_DIR}/${dir}" ]; then
            echo "Checking ${dir}..."
            for file in "${MODEL_DIR}/${dir}"/*; do
                if [ -f "$file" ]; then
                    if [ ! -s "$file" ]; then
                        echo "❌ Error: $file is empty"
                        all_valid=false
                    else
                        echo "✅ $file is valid"
                    fi
                fi
            done
        fi
    done
    
    if [ "$all_valid" = true ]; then
        return 0
    else
        return 1
    fi
}

if verify_all_downloads; then
    echo "✨ All models downloaded and verified successfully - NOW GO MAKE SOMETHING COOL"
    exit 0
else
    echo "⚠️ Some models may need to be re-downloaded"
    exit 1
fi