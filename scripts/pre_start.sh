#!/bin/bash
set -e  # Exit on error

export PYTHONUNBUFFERED=1
export PATH="/workspace/bin:$PATH"

# Ensure workspace directory exists with proper permissions
mkdir -p /workspace
chmod 755 /workspace

# Check and install additional nodes if needed
echo "**** CHECK NODES AND INSTALL IF NOT FOUND ****"
if [ "${SKIP_NODES}" == "true" ]; then
    echo "**** SKIPPING NODE INSTALLATION (SKIP_NODES=true) ****"
else
    /install_nodes.sh install_only
fi

# Download models if not skipped
if [ "${SKIP_DOWNLOADS}" == "true" ]; then
    echo "**** SKIPPING MODEL DOWNLOADS (SKIP_DOWNLOADS=true) ****"
else
    echo "**** DOWNLOADING - INSTALLING MODELS ****"
    /download_models.sh
fi

# Ensure proper permissions for ComfyUI
chmod -R 755 /workspace/ComfyUI

# 创建必要的目录
mkdir -p /workspace/ComfyUI/input
mkdir -p /workspace/ComfyUI/output
mkdir -p /workspace/ComfyUI/temp
chmod -R 755 /workspace/ComfyUI/input
chmod -R 755 /workspace/ComfyUI/output
chmod -R 755 /workspace/ComfyUI/temp

echo "✨ Pre-start completed successfully ✨"
