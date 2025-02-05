#!/bin/bash

# Directory containing the models
MODEL_BASE_DIR="/workspace/ComfyUI/models"

# Function to verify file size and redownload if necessary
verify_and_redownload() {
    local file_path="$1"
    local url="$2"
    local min_size=$((20 * 1024 * 1024))  # 20MB in bytes
    
    if [ -f "$file_path" ]; then
        local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path")
        echo "Checking $file_path (size: $((file_size/1024/1024))MB)"
        
        if [ "$file_size" -lt "$min_size" ]; then
            echo "Warning: $file_path is smaller than 20MB. Deleting and redownloading..."
            rm "$file_path"
            wget -O "$file_path" "$url"
            
            # Verify the newly downloaded file
            local new_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path")
            if [ "$new_size" -lt "$min_size" ]; then
                echo "Error: Failed to download $file_path correctly"
                return 1
            fi
        fi
    else
        echo "File $file_path not found. Downloading..."
        wget -O "$file_path" "$url"
    fi
}

# Array of model files and their URLs
declare -A MODEL_URLS=(
    ["${MODEL_BASE_DIR}/unet/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensor"
    ["${MODEL_BASE_DIR}/unet/hunyuan_video_720_cfgdistill_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors"
    ["${MODEL_BASE_DIR}/vae/hunyuan_video_vae_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors"
    ["${MODEL_BASE_DIR}/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"]="https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"
    ["${MODEL_BASE_DIR}/text_encoders/llava_llama3_fp8_scaled.safetensors"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors"
    ["${MODEL_BASE_DIR}/text_encoders/clip_l.safetensors"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/clip_l.safetensors"
    ["${MODEL_BASE_DIR}/clip_vision/clip-vit-large-patch14.safetensors"]="https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors"
    ["${MODEL_BASE_DIR}/loras/img2vid.safetensors"]="https://huggingface.co/leapfusion-image2vid-test/image2vid-512x320/resolve/main/img2vid.safetensors"
    ["${MODEL_BASE_DIR}/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"
)

# Create directories if they don't exist
mkdir -p "${MODEL_BASE_DIR}"/{diffusion_models,text_encoders,vae,clip_vision,loras,unet}

# Check and redownload each model if necessary
for file_path in "${!MODEL_URLS[@]}"; do
    verify_and_redownload "$file_path" "${MODEL_URLS[$file_path]}"
done

echo "Model verification complete!"

# Display final file sizes
echo -e "\nFinal file sizes:"
for file_path in "${!MODEL_URLS[@]}"; do
    if [ -f "$file_path" ]; then
        size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path")
        echo "$file_path: $((size/1024/1024))MB"
    else
        echo "$file_path: Not found"
    fi
done


    # ["${MODEL_BASE_DIR}/unet/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensor"
    # ["${MODEL_BASE_DIR}/unet/hunyuan_video_720_cfgdistill_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors"
    # ["${MODEL_BASE_DIR}/unet/hunyuan_video_t2v_720p_bf16.safetensors"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensors"
    # ["${MODEL_BASE_DIR}/vae/hunyuan_video_vae_bf16.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors"
    # ["${MODEL_BASE_DIR}/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"]="https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"
    # ["${MODEL_BASE_DIR}/text_encoders/llava_llama3_fp8_scaled.safetensors"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors"
    # ["${MODEL_BASE_DIR}/text_encoders/clip_l.safetensors"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/clip_l.safetensors"
    # ["${MODEL_BASE_DIR}/clip_vision/clip-vit-large-patch14.safetensors"]="https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors"
    # ["${MODEL_BASE_DIR}/loras/img2vid.safetensors"]="https://huggingface.co/leapfusion-image2vid-test/image2vid-512x320/resolve/main/img2vid.safetensors"
    # ["${MODEL_BASE_DIR}/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"]="https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"
    # ["${MODEL_BASE_DIR}/vae/hunyuan_video_vae_bf16_comfyorg"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/vae/hunyuan_video_vae_bf16.safetensors"
    # ["${MODEL_BASE_DIR}/text_encoders/llava_llama3_fp16.safetensors"]="https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp16.safetensors"
