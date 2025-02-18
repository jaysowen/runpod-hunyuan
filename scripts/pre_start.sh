#!/bin/bash
set -e  # Exit on error

export PYTHONUNBUFFERED=1
export PATH="/workspace/bin:$PATH"

# Ensure we have /workspace
mkdir -p /workspace

echo "**** CHECK NODES AND INSTALL IF NOT FOUND ****"
/install_nodes.sh install_only

echo "**** DOWNLOAD - INSTALLING MODELS ****"
/download_models.sh

if [[ ! -d /workspace/ComfyUI ]]; then
    # If we don't already have /workspace/ComfyUI, move it there
    echo "**** COPY COMFYUI TO WORKSPACE ****"
    mv /ComfyUI /workspace
else
    # otherwise delete the default ComfyUI folder which is always re-created on pod start from the Docker
    rm -rf /ComfyUI
fi

# Create symlink if it doesn't exist and isn't already linked
if [[ ! -L /ComfyUI ]] && [[ ! -d /ComfyUI ]]; then
    ln -s /workspace/ComfyUI /ComfyUI
fi

echo "✨ Pre-start completed successfully ✨"