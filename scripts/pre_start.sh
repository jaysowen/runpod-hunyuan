#!/bin/bash

set -e  # Exit on error

export PYTHONUNBUFFERED=1
export PATH="/workspace/bin:$PATH"

# Ensure we have /workspace in all scenarios
mkdir -p /workspace

if [[ ! -d /workspace/ComfyUI ]]; then
    # If we don't already have /workspace/ComfyUI, move it there
    mv /ComfyUI /workspace
else
    # otherwise delete the default ComfyUI folder which is always re-created on pod start from the Docker
    rm -rf /ComfyUI
fi

# Then link /ComfyUI folder to /workspace so it's available in that familiar location as well
ln -s /workspace/ComfyUI /ComfyUI

echo "**** DOWNLOAD - INSTALLING NODES ****"
bash /install_nodes.sh install_only

echo "**** DOWNLOAD -  ADDING MODELS ****"
bash /download_models.sh

echo "Pre-start completed successfully"