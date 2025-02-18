#!/bin/bash
# Exit on error, unset variables, and pipe failures
set -euo pipefail

MODEL_DIR="/ComfyUI/models"
mkdir -p ${MODEL_DIR}/{unet,text_encoders,clip_vision,vae,loras}

# Function to download file with retry limit
download_file() {
    local url=$1
    local dest=$2
    local filename=$(basename "$dest")
    local model_type=$(basename $(dirname "$dest"))
    local max_retries=3
    local retry_count=0

    if [ -f "$dest" ] && [ -s "$dest" ]; then
        echo "✅ $filename already exists in $model_type, skipping"
        return 0
    fi

    while [ $retry_count -lt $max_retries ]; do
        case "$filename" in
            "hunyuan_video_720_cfgdistill_bf16.safetensors")
                echo "🎭 Downloading Hunyuan Video UNet model..."
                ;;
            "hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors")
                echo "🚀 Downloading Hunyuan FastVideo LoRA..."
                ;;
            "Long-ViT-L-14-GmP-SAE-TE-only.safetensors")
                echo "🧠 Downloading LongCLIP Text Encoder..."
                ;;
            "llava_llama3_fp8_scaled.safetensors")
                echo "🦙 Downloading Llava Text Encoder..."
                ;;
            "hunyuan_video_vae_bf16.safetensors")
                echo "🎨 Downloading Hunyuan Video VAE..."
                ;;
            "clip-vit-large-patch14.safetensors")
                echo "👁️ Downloading CLIP Vision model..."
                ;;
        esac

        if wget --progress=dot:giga -O "$dest.tmp" "$url" 2>&1 | grep --line-buffered "%" | sed -u -e "s,\.,,g" | awk '{printf("\r%4s", $2)}'; then
            mv "$dest.tmp" "$dest"
            echo -e "\n✨ Successfully downloaded $filename"
            echo "----------------------------------------"
            return 0
        else
            echo -e "\n⚠️ Failed to download $filename (attempt $((retry_count + 1))/$max_retries)"
            rm -f "$dest.tmp"
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo "Retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done

    echo "❌ Failed to download $filename after $max_retries attempts"
    return 1
}

echo "🚀 Starting model downloads..."

# Define download tasks
declare -A downloads=(
    ["${MODEL_DIR}/unet/hunyuan_video_720_cfgdistill_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors"
    ["${MODEL_DIR}/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"
    ["${MODEL_DIR}/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"]="https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"
    ["${MODEL_DIR}/text_encoders/llava_llama3_fp8_scaled.safetensors"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors"
    ["${MODEL_DIR}/vae/hunyuan_video_vae_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors"
    ["${MODEL_DIR}/clip_vision/clip-vit-large-patch14.safetensors"]="https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors"
)

# Track overall success
download_success=true

# Download files sequentially
for dest in "${!downloads[@]}"; do
    url="${downloads[$dest]}"
    if ! download_file "$url" "$dest"; then
        download_success=false
        echo "⚠️ Failed to download $(basename "$dest") - continuing with other downloads"
    fi
done

# Final verification
echo "🔍 Verifying downloads..."
verification_failed=false
for dir in "unet" "loras" "text_encoders" "clip_vision" "vae"; do
    if [ -d "${MODEL_DIR}/${dir}" ]; then
        for file in "${MODEL_DIR}/${dir}"/*; do
            if [ -f "$file" ]; then
                if [ ! -s "$file" ]; then
                    echo "❌ Error: $(basename "$file") is empty"
                    verification_failed=true
                else
                    echo "✅ $(basename "$file") verified successfully"
                fi
            fi
        done
    fi
done

# Create a status file to prevent re-runs
touch "${MODEL_DIR}/.downloads_completed"

if [ "$download_success" = true ] && [ "$verification_failed" = false ]; then
    echo "✨ All models downloaded and verified successfully - Starting ComfyUI..."
    exit 0
else
    echo "⚠️ Some models failed to download but continuing with available models..."
    exit 0  # Still exit with 0 to allow ComfyUI to start
fi