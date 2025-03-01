#!/bin/bash
set -euo pipefail

# Base directory for models
MODEL_DIR="/ComfyUI/models"
mkdir -p ${MODEL_DIR}/{checkpoints,loras,embeddings,controlnet,vae,unet}

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

# Function to get file size from URLs
get_file_size() {
    local url="$1"
    local size=0
    
    if [[ $url == *"huggingface.co"* ]]; then
        local redirect_url=$(curl -sIL "$url" | grep -i "location:" | tail -n 1 | awk '{print $2}' | tr -d '\r')
        if [ -n "$redirect_url" ]; then
            size=$(curl -sI "$redirect_url" | grep -i content-length | tail -n 1 | awk '{print $2}' | tr -d '\r')
        else
            size=$(curl -sI "$url" | grep -i content-length | tail -n 1 | awk '{print $2}' | tr -d '\r')
        fi
    elif [[ $url == *"civitai.com"* ]]; then
        size=$(curl -sI "$url" | grep -i content-length | tail -n 1 | awk '{print $2}' | tr -d '\r')
    fi
    
    echo "${size:-0}"
}

download_file() {
    local url="$1"
    local dest="$2"
    local type="$3"
    local filename=$(basename "$dest")
    local model_type=$(basename $(dirname "$dest"))
    
    if [ -f "$dest" ] && [ -s "$dest" ]; then
        echo "✅ $filename already exists in $model_type"
        return 0
    fi

    echo "📥 Starting download: $filename"
    echo "📂 Type: $model_type"
    
    if [ "$type" = "gdrive" ]; then
        echo "🔄 Downloading from Google Drive..."
        if gdown --fuzzy "$url" -O "$dest.tmp"; then
            mv "$dest.tmp" "$dest"
            echo "✨ Completed: $filename"
            return 0
        else
            echo "❌ Failed to download $filename from Google Drive"
            rm -f "$dest.tmp"
            return 1
        fi
    else
        local size=$(get_file_size "$url")
        local formatted_size=$(format_size "$size")
        echo "📊 Total size: $formatted_size"
        
        wget --progress=dot:mega \
             -O "$dest.tmp" \
             "$url" 2>&1 | \
        stdbuf -o0 awk '
        /[0-9]+%/ {
            match($0, /([0-9]+)%/)
            current = substr($0, RSTART, RLENGTH - 1)
            if (current % 10 == 0 && current != last_printed) {
                last_printed = current
                printf "⏳ %s: %3d%%\n", FILENAME, current
            }
        }'
        
        mv "$dest.tmp" "$dest"
        echo "✨ Completed: $filename"
    fi
}

# Check if files.txt exists
CONFIG_FILE="/workspace/files.txt"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: files.txt not found in workspace directory"
    echo "Please create a files.txt file with the following format:"
    echo "type|folder|filename|url"
    echo "Example:"
    echo "normal|checkpoints|model1.safetensors|https://huggingface.co/path/to/model1.safetensors"
    echo "gdrive|loras|lora1.safetensors|https://drive.google.com/uc?id=your_file_id"
    echo "normal|unet|unet_model.safetensors|https://huggingface.co/path/to/unet.safetensors"
    exit 1
fi

# Read downloads from config file
declare -a downloads
while IFS='|' read -r type folder filename url || [ -n "$type" ]; do
    # Skip empty lines and comments
    if [[ -z "$type" || "$type" == \#* ]]; then
        continue
    fi
    downloads+=("$type|${MODEL_DIR}/${folder}/${filename}|$url")
done < "$CONFIG_FILE"

if [ ${#downloads[@]} -eq 0 ]; then
    echo "❌ Error: No valid download entries found in files.txt"
    exit 1
fi

echo "🚀 Starting model downloads..."
echo "📋 Found ${#downloads[@]} models to download"

download_success=true
total_files=${#downloads[@]}
current_file=1

for download in "${downloads[@]}"; do
    IFS='|' read -r type dest url <<< "$download"
    echo -e "\n📦 Processing file $current_file of $total_files"
    if ! download_file "$url" "$dest" "$type"; then
        download_success=false
        echo "⚠️ Failed to download $(basename "$dest") - continuing with other downloads"
    fi
    current_file=$((current_file + 1))
done

# Verify downloads
echo -e "\n🔍 Verifying downloads..."
verification_failed=false

for download in "${downloads[@]}"; do
    IFS='|' read -r type dest url <<< "$download"
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
