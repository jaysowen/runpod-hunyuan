#!/bin/bash
set -e  # Exit on error

# Ensure we're starting in a valid directory
cd /

# Check if files exist in workspace, copy from root if not
if [ ! -f "/workspace/download-files.sh" ]; then
    echo "🔄 Copying download-files.sh to workspace"
    if [ -f "/download-files.sh" ]; then
        cp /download-files.sh /workspace/
        chmod +x /workspace/download-files.sh
        echo "✅ Copied download-files.sh to workspace"
    else
        echo "❌ download-files.sh not found in root directory"
    fi
fi

if [ ! -f "/workspace/files.txt" ]; then
    echo "🔄 Copying files.txt to workspace"
    if [ -f "/files.txt" ]; then
        cp /files.txt /workspace/
        echo "✅ Copied files.txt to workspace"
    else
        echo "❌ files.txt not found in root directory"
    fi
fi

echo "⭐⭐⭐⭐⭐   ALL DONE - STARTING COMFYUI ⭐⭐⭐⭐⭐"

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Change to ComfyUI directory
cd /workspace/ComfyUI

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "runpod-worker-comfy: Starting ComfyUI"
    python3 main.py --disable-auto-launch --disable-metadata --listen &

    echo "runpod-worker-comfy: Starting RunPod Handler"
    python3 -u /rp_handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    echo "runpod-worker-comfy: Starting ComfyUI"
    python3 main.py --disable-auto-launch --disable-metadata &

    echo "runpod-worker-comfy: Starting RunPod Handler"
    python3 -u /rp_handler.py
fi