#!/bin/bash
set -euo pipefail

# Define MODEL_DIR relative to the ComfyUI installation within the workspace
# This needs to align with where pre_start.sh expects them after potential moves/symlinks.
WORKSPACE_MODEL_ROOT="/workspace/ComfyUI/models"

# Define download tasks with their respective target subdirectories and URLs
declare -A downloads=(
    ["diffusion_models/wan2.1_i2v_480p_14B_fp16.safetensors"]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_i2v_480p_14B_fp16.safetensors"
    ["loras/Titty_Drop_Wan_2.1_LoRA.safetensors"]="https://huggingface.co/jaysowen/wan_loras/resolve/main/Titty_Drop_Wan_2.1_LoRA.safetensors"
    ["loras/wan_female_masturbation.safetensors"]="https://huggingface.co/jaysowen/wan_loras/resolve/main/Wan_Female_Masturbation.safetensors"
    ["text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
    ["clip_vision/clip_vision_h.safetensors"]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
    ["vae/wan_2.1_vae.safetensors"]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
)

# If --list-files argument is provided, print expected final paths and exit
if [[ "${1:-}" == "--list-files" ]]; then
    for relative_path in "${!downloads[@]}"; do
        echo "${WORKSPACE_MODEL_ROOT}/${relative_path}"
    done
    exit 0
fi


# Exit immediately if SKIP_DOWNLOADS is set to true
if [ "${SKIP_DOWNLOADS:-false}" == "true" ]; then
    echo "SKIP_DOWNLOADS is set to true, skipping model downloads"
    exit 0
fi

# Original MODEL_DIR for download destination within the temporary build context
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
    # Use the original MODEL_DIR for the temporary download location
    local dest_relative_path="$2"
    local dest="${MODEL_DIR}/${dest_relative_path}"
    local filename=$(basename "$dest")
    local model_type=$(basename $(dirname "$dest"))

    # Ensure the target directory exists before downloading
    mkdir -p "$(dirname "$dest")"

    # 如果文件存在，直接跳过下载
    if [ -f "$dest" ]; then
        echo "✅ $filename already exists in $model_type (temporary location), skipping download"
        # Even if it exists here, pre_start.sh checks the final workspace location
        return 0
    fi

    echo "📥 Starting download: $filename to temporary location"

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
    echo "✨ Completed: $filename (downloaded to temporary location)"
}

echo "🚀 Starting model downloads (if needed)..."


total_files=${#downloads[@]}
current_file=1
download_success=true

# Loop through relative paths defined in the array keys
for dest_relative_path in "${!downloads[@]}"; do
    url="${downloads[$dest_relative_path]}"
    echo -e "\n📦 Processing file $current_file of $total_files"
    # Pass the relative path to download_file
    if ! download_file "$url" "$dest_relative_path"; then
        download_success=false
        echo "⚠️ Failed to download $(basename "$dest_relative_path") - continuing with other downloads"
    fi
    current_file=$((current_file + 1))
done


# Verification logic needs to check the temporary download location
echo -e "\n🔍 Verifying downloads in temporary location (${MODEL_DIR})..."
verification_failed=false

# Verify each file in its temporary directory
for dest_relative_path in "${!downloads[@]}"; do
    dir=$(dirname "$dest_relative_path")
    file=$(basename "$dest_relative_path")
    # Check path relative to the temporary MODEL_DIR
    full_path="$MODEL_DIR/$dir/$file" # Corrected path for verification

    if [ -f "$full_path" ]; then
        size=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo 0)
        if [ "$size" -eq 0 ]; then
            echo "❌ Error: $file is empty in temporary $dir directory"
            verification_failed=true
        else
            formatted_size=$(format_size "$size")
            echo "✅ $file verified successfully in temporary $dir directory ($formatted_size)"
        fi
    else
        echo "❌ Error: $file is missing from temporary $dir directory after download attempt"
        verification_failed=true
    fi
done

# Report success/failure based on temporary download location checks
if [ "$download_success" = true ] && [ "$verification_failed" = false ]; then
    echo -e "\n✨ All models downloaded and verified successfully to temporary location."
    exit 0
else
    echo -e "\n⚠️ Some models failed to download or verify in temporary location."
    # Exit with error code 1 if download/verification failed here
    exit 1
fi

# Note: The actual move/symlink to /workspace happens in pre_start.sh
