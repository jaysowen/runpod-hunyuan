#!/bin/bash

# Function to handle errors
handle_error() {
    echo "Error: $1"
    exit 1
}

# Set up logging
exec 1> >(tee -a /workspace/startup.log)
exec 2> >(tee -a /workspace/startup.log >&2)

echo "Starting services at $(date)"

# Create necessary directories if they don't exist
mkdir -p /workspace/ComfyUI/output || handle_error "Failed to create output directory"
mkdir -p /workspace/logs || handle_error "Failed to create logs directory"

# Start code-server (VS Code)
echo "Starting VS Code server..."
code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/logs/vscode.log 2>&1 &
VSCODE_PID=$!
echo "VS Code server started with PID: $VSCODE_PID"

# Wait a moment to ensure VS Code server is running
sleep 2

# Check if VS Code server is running
if ! kill -0 $VSCODE_PID 2>/dev/null; then
    handle_error "VS Code server failed to start"
fi

# Start ComfyUI
echo "Starting ComfyUI..."
cd /workspace/ComfyUI || handle_error "Failed to change to ComfyUI directory"

# Activate virtual environment if it exists
if [ -d "/opt/venv" ]; then
    echo "Activating virtual environment..."
    source /opt/venv/bin/activate || handle_error "Failed to activate virtual environment"
fi

# Set CUDA device if available
if [ -e "/proc/driver/nvidia/version" ]; then
    echo "NVIDIA driver detected, setting up CUDA environment..."
    export CUDA_VISIBLE_DEVICES=all
fi

# Start ComfyUI with proper parameters
python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /workspace/logs/comfyui.log 2>&1 &
COMFY_PID=$!
echo "ComfyUI started with PID: $COMFY_PID"

# Wait a moment to ensure ComfyUI is running
sleep 5

# Check if ComfyUI is running
if ! kill -0 $COMFY_PID 2>/dev/null; then
    handle_error "ComfyUI failed to start"
fi

echo "All services started successfully!"

# Keep the script running and monitor processes
while true; do
    if ! kill -0 $VSCODE_PID 2>/dev/null; then
        echo "VS Code server crashed, restarting..."
        code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/logs/vscode.log 2>&1 &
        VSCODE_PID=$!
    fi
    
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        echo "ComfyUI crashed, restarting..."
        cd /workspace/ComfyUI
        python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /workspace/logs/comfyui.log 2>&1 &
        COMFY_PID=$!
    fi
    
    sleep 10
done