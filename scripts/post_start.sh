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

# Add this to post_start.sh
if [ ! -f "/workspace/run_image_browser.sh" ]; then
    echo "🔄 Copying run_image_browser.sh to workspace"
    if [ -f "/run_image_browser.sh" ]; then
        cp /run_image_browser.sh /workspace/
        chmod +x /workspace/run_image_browser.sh
        echo "✅ Copied run_image_browser.sh to workspace"
    elif [ -f "/manage-files/run_image_browser.sh" ]; then
        cp /manage-files/run_image_browser.sh /workspace/
        chmod +x /workspace/run_image_browser.sh
        echo "✅ Copied run_image_browser.sh from manage-files to workspace"
    else
        echo "❌ run_image_browser.sh not found"
    fi
fi

echo "⭐⭐⭐⭐⭐   ALL DONE - STARTING COMFYUI ⭐⭐⭐⭐⭐"

# Change to ComfyUI directory and start the server
cd /workspace/ComfyUI
python main.py --listen --port 8188 --enable-cors-header $COMFYUI_EXTRA_ARGS &

echo "🖼️ Starting Infinite Image Browser..."
chmod +x /workspace/run_image_browser.sh
nohup /workspace/run_image_browser.sh
echo "Infinite Image Browser started on port 8181"