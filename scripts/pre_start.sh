#!/bin/bash
set -e  # Exit on error

export PYTHONUNBUFFERED=1
export PATH="/workspace/bin:$PATH"

# Ensure we have /workspace
mkdir -p /workspace

# Handle ComfyUI directory
if [[ ! -d /workspace/ComfyUI ]]; then
    if [[ -d /ComfyUI ]]; then
        mv /ComfyUI /workspace/
    else
        git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
    fi
fi

# Create symlink if it doesn't exist and isn't already linked
if [[ ! -L /ComfyUI ]] && [[ ! -d /ComfyUI ]]; then
    ln -s /workspace/ComfyUI /ComfyUI
fi

echo "**** DOWNLOAD - INSTALLING NODES ****"
bash /install_nodes.sh install_only

echo "**** DOWNLOAD -  ADDING MODELS ****"
bash /download_models.sh

echo "Pre-start completed successfully"