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

# # Create the ComfyUI directory in workspace if it doesn't exist
mkdir -p /workspace/ComfyUI

echo "MOVING COMFYUI TO WORKSPACE"
# Check if /ComfyUI exists and is not already a symlink
if [ -d "/ComfyUI" ] && [ ! -L "/ComfyUI" ]; then
    echo "**** SETTING UP COMFYUI IN WORKSPACE ****"
    # Remove destination directory if it exists
    rm -rf /workspace/ComfyUI
    # Move the entire ComfyUI directory to workspace
    mv /ComfyUI/* /workspace/ComfyUI/
    mv /ComfyUI/.* /workspace/ComfyUI/ 2>/dev/null || true
    rmdir /ComfyUI
    # Create symlink
    ln -sf /workspace/ComfyUI /ComfyUI
fi

# Ensure proper permissions
chmod -R 755 /workspace/ComfyUI

echo "✨ Pre-start completed successfully ✨"