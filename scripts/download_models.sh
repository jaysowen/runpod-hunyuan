#!/bin/bash
set -e

MODEL_DIR="/workspace/ComfyUI/models"
mkdir -p ${MODEL_DIR}/{unet,text_encoders,clip_vision,vae}

# Maximum number of parallel downloads
MAX_PARALLEL=3
current_parallel=0

# Function to verify file integrity using SHA256
verify_checksum() {
    local file=$1
    local expected_sha=$2
    
    if [ -f "$file" ]; then
        local actual_sha=$(sha256sum "$file" | cut -d' ' -f1)
        if [ "$actual_sha" = "$expected_sha" ]; then
            return 0
        fi
    fi
    return 1
}

# Function to download with progress and verification
download_with_verification() {
    local url=$1
    local dest=$2
    local sha256=$3
    local filename=$(basename "$dest")
    local temp_dest="${dest}.downloading"
    
    # Check if file exists and is valid
    if [ -f "$dest" ]; then
        if [ -z "$sha256" ] || verify_checksum "$dest" "$sha256"; then
            echo "✅ $filename already exists and is valid, skipping download"
            return 0
        else
            echo "🔄 $filename exists but is invalid, re-downloading..."
            rm -f "$dest"
        fi
    fi

    echo "⬇️ Downloading $filename..."
    wget -q --show-progress "$url" -O "$temp_dest"
    
    if [ -z "$sha256" ] || verify_checksum "$temp_dest" "$sha256"; then
        mv "$temp_dest" "$dest"
        echo "✅ Downloaded and verified $filename successfully"
    else
        rm -f "$temp_dest"
        echo "❌ Failed to verify $filename"
        return 1
    fi
}

# Function to process download in parallel
download_parallel() {
    local url=$1
    local dest=$2
    local sha256=$3
    
    download_with_verification "$url" "$dest" "$sha256" &
    
    ((current_parallel++))
    
    if [ $current_parallel -ge $MAX_PARALLEL ]; then
        wait
        current_parallel=0
    fi
}

# Declare model arrays with their details
declare -A UNET_MODELS=(
    ["hunyuan_video_720_cfgdistill_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors"
    ["hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"
)

declare -A TEXT_ENCODERS_MODELS=(
    ["Long-ViT-L-14-GmP-SAE-TE-only.safetensors"]="https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"
    ["llava_llama3_fp8_scaled.safetensors"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors"
)

declare -A VAE_MODELS=(
    ["hunyuan_video_vae_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors"
)

declare -A CLIP_VISION_MODELS=(
    ["clip-vit-large-patch14.safetensors"]="https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors"
)

echo "🚀 Starting model downloads..."

# Download UNET Models
echo "⭐ Processing UNET Models..."
for model in "${!UNET_MODELS[@]}"; do
    download_parallel "${UNET_MODELS[$model]}" "${MODEL_DIR}/unet/$model"
done
wait
current_parallel=0

# Download Text Encoders Models
echo "📝 Processing Text Encoders Models..."
for model in "${!TEXT_ENCODERS_MODELS[@]}"; do
    download_parallel "${TEXT_ENCODERS_MODELS[$model]}" "${MODEL_DIR}/text_encoders/$model"
done
wait
current_parallel=0

# Download VAE Models
echo "🎨 Processing VAE Models..."
for model in "${!VAE_MODELS[@]}"; do
    download_parallel "${VAE_MODELS[$model]}" "${MODEL_DIR}/vae/$model"
done
wait
current_parallel=0

# Download CLIP Vision Models
echo "👁️ Processing CLIP Vision Models..."
for model in "${!CLIP_VISION_MODELS[@]}"; do
    download_parallel "${CLIP_VISION_MODELS[$model]}" "${MODEL_DIR}/clip_vision/$model"
done
wait

# Verify all downloads
echo "🔍 Verifying all downloads..."
verify_all_downloads() {
    local all_valid=true
    
    for dir in "unet" "text_encoders" "clip_vision" "vae"; do
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
    
    return $all_valid
}

if verify_all_downloads; then
    echo "✨ All models downloaded and verified successfully"
else
    echo "⚠️ Some models may need to be re-downloaded"
    exit 1
fi

# Run the node installation script
/install_nodes.sh