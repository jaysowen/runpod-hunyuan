#!/bin/bash
set -e  # Exit on error

export PYTHONUNBUFFERED=1
export PATH="/workspace/bin:$PATH"

# Ensure workspace directory exists
mkdir -p /workspace

echo "**** CHECK NODES AND INSTALL IF NOT FOUND ****"
/install_nodes.sh install_only

echo "**** DOWNLOAD - INSTALLING MODELS ****"
/download_models.sh

# Create the ComfyUI directory in workspace if it doesn't exist
mkdir -p /workspace/ComfyUI

# If /ComfyUI exists (original copy), move its contents to /workspace/ComfyUI
if [ -d "/ComfyUI" ]; then
    echo "**** COPY COMFYUI TO WORKSPACE ****"
    # Use cp instead of mv to preserve original files
    cp -r /ComfyUI/* /workspace/ComfyUI/
    # Remove the original ComfyUI directory
    rm -rf /ComfyUI
fi

# Create symlink if it doesn't exist
if [[ ! -L "/ComfyUI" ]]; then
    ln -sf /workspace/ComfyUI /ComfyUI
fi

# Ensure proper permissions
chmod -R 755 /workspace/ComfyUI

echo "✨ Pre-start completed successfully ✨"