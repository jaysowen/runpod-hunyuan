#!/bin/bash

# Function to handle errors
handle_error() {
    echo "Error: $1"
    exit 1
}

echo "Starting services at $(date)"

# Verify ComfyUI installation
if [ ! -d "/workspace/ComfyUI" ]; then
    handle_error "ComfyUI installation not found in /workspace"
fi

# Start VS Code server
echo "Starting VS Code server..."
code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/logs/vscode.log 2>&1 &
VSCODE_PID=$!

# Start Jupyter Lab
echo "Starting Jupyter Lab..."
jupyter lab --allow-root --ip=0.0.0.0 --port=8888 --no-browser > /workspace/logs/jupyter.log 2>&1 &
JUPYTER_PID=$!

# Start ComfyUI
echo "Starting ComfyUI..."
cd /workspace/ComfyUI || handle_error "Failed to change to ComfyUI directory"
python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header --verbose > /workspace/logs/comfyui.log 2>&1 &
COMFY_PID=$!

echo "Services started. Monitoring processes..."

# Monitor processes
while true; do
    if ! kill -0 $VSCODE_PID 2>/dev/null; then
        echo "VS Code server crashed, restarting..."
        code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/logs/vscode.log 2>&1 &
        VSCODE_PID=$!
    fi
    
    if ! kill -0 $JUPYTER_PID 2>/dev/null; then
        echo "Jupyter Lab crashed, restarting..."
        jupyter lab --allow-root --ip=0.0.0.0 --port=8888 --no-browser > /workspace/logs/jupyter.log 2>&1 &
        JUPYTER_PID=$!
    fi
    
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        echo "ComfyUI crashed, restarting..."
        cd /workspace/ComfyUI || handle_error "Failed to change to ComfyUI directory"
        python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header --verbose > /workspace/logs/comfyui.log 2>&1 &
        COMFY_PID=$!
    fi
    
    sleep 10
done