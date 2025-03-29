#!/bin/bash
set -euo pipefail

# Exit immediately if SKIP_DOWNLOADS is set to true
if [ "${SKIP_DOWNLOADS:-false}" == "true" ]; then
    echo "SKIP_DOWNLOADS is set to true, skipping model downloads"
    exit 0
fi

MODEL_DIR="/ComfyUI/models"
mkdir -p ${MODEL_DIR}/{unet,text_encoders,clip_vision,vae,loras,diffusion_models}

# Function to format file size
format_size() {
    local size="${1:-0}"
    if [ "$size" -eq 0 ]; then
        echo "unknown size"
        return
    fi
    if [ "$size" -ge 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $size/1073741824}") GB"
    elif [ "$size" -ge 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $size/1048576}") MB"
    elif [ "$size" -ge 1024 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $size/1024}") KB"
    else
        echo "${size} B"
    fi
}

# Function to get true file size from Hugging Face
get_hf_file_size() {
    local url="$1"
    local size=0
    
    local redirect_url=$(curl -sIL "$url" | grep -i "location:" | tail -n 1 | awk '{print $2}' | tr -d '\r')
    
    if [ -n "$redirect_url" ]; then
        size=$(curl -sI "$redirect_url" | grep -i content-length | tail -n 1 | awk '{print $2}' | tr -d '\r')
    else
        size=$(curl -sI "$url" | grep -i content-length | tail -n 1 | awk '{print $2}' | tr -d '\r')
    fi
    
    echo "${size:-0}"
}

download_file() {
    local url="$1"
    local dest="$2"
    local filename=$(basename "$dest")
    local model_type=$(basename $(dirname "$dest"))
    
    if [ -f "$dest" ] && [ -s "$dest" ]; then
        echo "✅ $filename already exists in $model_type"
        return 0
    fi

    echo "📥 Starting download: $filename"
    
    wget --progress=dot:mega \
         -O "$dest.tmp" \
         "$url" 2>&1 | \
    stdbuf -o0 awk '
    /[0-9]+%/ {
        # Only print every 10% to reduce log spam
        match($0, /([0-9]+)%/)
        current = substr($0, RSTART, RLENGTH - 1)
        if (current % 10 == 0 && current != last_printed) {
            last_printed = current
            printf "⏳ %s: %3d%%\n", FILENAME, current
        }
    }'
    
    mv "$dest.tmp" "$dest"
    echo "✨ Completed: $filename"
}

echo "🚀 Starting model downloads..."

# Initialize downloads array
declare -A downloads

# First, add the default models
downloads["${MODEL_DIR}/diffusion_models/wan2.1_i2v_480p_14B_fp16.safetensors"]="https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors"
downloads["${MODEL_DIR}/clip_vision/clip_vision_h.safetensors"]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
downloads["${MODEL_DIR}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
downloads["${MODEL_DIR}/vae/wan_2.1_vae.safetensors"]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"

# Then, read and add models from files.txt
if [ -f "/workspace/files.txt" ]; then
    echo "📄 Reading additional models from /workspace/files.txt"
    while IFS='|' read -r model_type filename url || [ -n "$model_type" ]; do
        # Skip empty lines and comments
        if [[ -z "$model_type" || "$model_type" =~ ^# ]]; then
            continue
        fi
        # Remove any whitespace
        model_type=$(echo "$model_type" | tr -d '[:space:]')
        filename=$(echo "$filename" | tr -d '[:space:]')
        url=$(echo "$url" | tr -d '[:space:]')
        
        if [ -n "$model_type" ] && [ -n "$filename" ] && [ -n "$url" ]; then
            dest="${MODEL_DIR}/${model_type}/${filename}"
            downloads["$dest"]="$url"
            echo "➕ Added from files.txt: ${model_type}/${filename}"
        fi
    done < "/workspace/files.txt"
else
    echo "⚠️ Warning: /workspace/files.txt not found"
fi

download_success=true
total_files=${#downloads[@]}
current_file=1

for dest in "${!downloads[@]}"; do
    url="${downloads[$dest]}"
    echo -e "\n📦 Processing file $current_file of $total_files"
    if ! download_file "$url" "$dest"; then
        download_success=false
        echo "⚠️ Failed to download $(basename "$dest") - continuing with other downloads"
    fi
    current_file=$((current_file + 1))
done

# Fixed verification logic that only checks files in their correct directories
echo -e "\n🔍 Verifying downloads..."
verification_failed=false

# Create a mapping of files to their expected directories
declare -A expected_files
for dest in "${!downloads[@]}"; do
    dir=$(basename $(dirname "$dest"))
    file=$(basename "$dest")
    expected_files["$dir/$file"]=1
done

# Verify each file in its correct directory
for dest in "${!downloads[@]}"; do
    dir=$(basename $(dirname "$dest"))
    file=$(basename "$dest")
    full_path="$MODEL_DIR/$dir/$file"
    
    if [ -f "$full_path" ]; then
        size=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path")
        if [ "$size" -eq 0 ]; then
            echo "❌ Error: $file is empty in $dir directory"
            verification_failed=true
        else
            formatted_size=$(format_size "$size")
            echo "✅ $file verified successfully in $dir directory ($formatted_size)"
        fi
    else
        echo "❌ Error: $file is missing from $dir directory"
        verification_failed=true
    fi
done

if [ "$download_success" = true ] && [ "$verification_failed" = false ]; then
    echo -e "\n✨ All models downloaded and verified successfully"
    exit 0
else
    echo -e "\n⚠️ Some models failed to download or verify"
    exit 1
fi