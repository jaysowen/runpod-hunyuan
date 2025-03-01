#!/bin/bash
set -e  # Exit on error

# Check if download-files.sh and files.txt exist in /workspace
if [ ! -f "/workspace/download-files.sh" ] || [ ! -f "/workspace/files.txt" ]; then
    echo "🔄 Copying missing download-files.sh and/or files.txt to /workspace"
    
    # Check if files exist in the /manage-files/ directory
    if [ -f "/manage-files/download-files.sh" ]; then
        cp /manage-files/download-files.sh /workspace/
        chmod +x /workspace/download-files.sh
        echo "✅ Copied download-files.sh to /workspace"
    else
        echo "❌ download-files.sh not found in root directory"
    fi
    
    if [ -f "/manage-files/files.txt" ]; then
        cp /manage-files/files.txt /workspace/
        echo "✅ Copied files.txt to /workspace"
    else
        echo "❌ files.txt not found in root directory"
    fi
fi

echo "⭐⭐⭐⭐⭐   ALL DONE - STARTING COMFYUI ⭐⭐⭐⭐⭐"

# Change to ComfyUI directory and start the server
cd /workspace/ComfyUI
python main.py --listen --port 8188 --enable-cors-header $COMFYUI_EXTRA_ARGS &