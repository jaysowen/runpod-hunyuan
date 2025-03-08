#!/bin/bash
set -e  # Exit on error

export PYTHONUNBUFFERED=1
export PATH="/workspace/bin:$PATH"

# Ensure workspace directory exists with proper permissions
mkdir -p /workspace
chmod 755 /workspace

echo "**** CHECK NODES AND INSTALL IF NOT FOUND ****"
if [ "${SKIP_NODES}" == "true" ]; then
    echo "**** SKIPPING NODE INSTALLATION (SKIP_NODES=true) ****"
else
    /install_nodes.sh install_only
fi

# Check if downloads should be skipped
if [ "${SKIP_DOWNLOADS}" == "true" ]; then
    echo "**** SKIPPING MODEL DOWNLOADS (SKIP_DOWNLOADS=true) ****"
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


echo "MOVING SD GALLERY to workspace"
# Ensure clean workspace/ComfyUI directory setup
if [ -e "/workspace/sd-webui-infinite-image-browsing" ]; then
    if [ ! -d "/workspace/sd-webui-infinite-image-browsing" ]; then
        echo "Removing invalid /workspace/sd-webui-infinite-image-browsing"
        rm -f /workspace/sd-webui-infinite-image-browsing
    fi
fi

# Create fresh ComfyUI directory
mkdir -p /workspace/sd-webui-infinite-image-browsing
chmod 755 /workspace/sd-webui-infinite-image-browsing

# Check if /ComfyUI exists and is not already a symlink
if [ -d "/sd-webui-infinite-image-browsing" ] && [ ! -L "/sd-webui-infinite-image-browsing" ]; then
    echo "**** SETTING UP sd-webui-infinite-image-browsing IN WORKSPACE ****"
    # Copy files instead of moving to avoid potential issues
    cp -rf /sd-webui-infinite-image-browsing/* /workspace/sd-webui-infinite-image-browsing/
    cp -rf /sd-webui-infinite-image-browsing/.??* /workspace/sd-webui-infinite-image-browsing/ 2>/dev/null || true
    rm -rf /sd-webui-infinite-image-browsing
    # Create symlink
    ln -sf /workspace/sd-webui-infinite-image-browsing /sd-webui-infinite-image-browsing
fi

echo "✨ Pre-start completed successfully ✨"