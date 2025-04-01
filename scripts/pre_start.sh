#!/bin/bash
set -e  # Exit on error

export PYTHONUNBUFFERED=1
export PATH="/workspace/bin:$PATH"

# Ensure workspace directory exists with proper permissions
mkdir -p /workspace
chmod 755 /workspace

# Check if models are already downloaded
check_models_downloaded() {
    local required_models=(
        "/workspace/ComfyUI/models/diffusion_models/wan2.1_i2v_480p_14B_fp16.safetensors"
        "/workspace/ComfyUI/models/loras/Titty_Drop_Wan_2.1_LoRA.safetensors"
        "/workspace/ComfyUI/models/loras/wan_female_masturbation.safetensors"
        "/workspace/ComfyUI/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
        "/workspace/ComfyUI/models/clip_vision/clip_vision_h.safetensors"
        "/workspace/ComfyUI/models/vae/wan_2.1_vae.safetensors"
    )
    
    for model in "${required_models[@]}"; do
        if [ ! -f "$model" ] || [ ! -s "$model" ]; then
            return 1
        fi
    done
    return 0
}

echo "**** CHECK NODES AND INSTALL IF NOT FOUND ****"
if [ "${SKIP_NODES}" == "true" ]; then
    echo "**** SKIPPING NODE INSTALLATION (SKIP_NODES=true) ****"
else
    /install_nodes.sh install_only
fi

# Check if downloads should be skipped
if [ "${SKIP_DOWNLOADS}" == "true" ]; then
    echo "**** SKIPPING MODEL DOWNLOADS (SKIP_DOWNLOADS=true) ****"
elif check_models_downloaded; then
    echo "**** MODELS ALREADY DOWNLOADED, SKIPPING DOWNLOAD ****"
else
    echo "**** DOWNLOADING - INSTALLING MODELS ****"
    /download_models.sh
fi

echo "MOVING COMFYUI TO WORKSPACE"
# Ensure clean workspace/ComfyUI directory setup
if [ -e "/workspace/ComfyUI" ]; then
    if [ ! -d "/workspace/ComfyUI" ]; then
        echo "Removing invalid /workspace/ComfyUI"
        rm -f /workspace/ComfyUI
    fi
fi

# Create fresh ComfyUI directory
mkdir -p /workspace/ComfyUI
chmod 755 /workspace/ComfyUI

# Check if /ComfyUI exists and is not already a symlink
if [ -d "/ComfyUI" ] && [ ! -L "/ComfyUI" ]; then
    echo "**** SETTING UP COMFYUI IN WORKSPACE ****"
    # Copy files instead of moving to avoid potential issues
    cp -rf /ComfyUI/* /workspace/ComfyUI/
    cp -rf /ComfyUI/.??* /workspace/ComfyUI/ 2>/dev/null || true
    rm -rf /ComfyUI
    # Create symlink
    ln -sf /workspace/ComfyUI /ComfyUI
fi

# Ensure proper permissions
chmod -R 755 /workspace/ComfyUI

echo "✨ Pre-start completed successfully ✨"
