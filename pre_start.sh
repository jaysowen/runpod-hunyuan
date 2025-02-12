#!/bin/bash

# Function to handle errors
handle_error() {
    echo "Error: $1"
    if [ -f /workspace/logs/comfyui.log ]; then
        echo "ComfyUI Log Output:"
        tail -n 50 /workspace/logs/comfyui.log
    fi
    exit 1
}

# Set up logging
exec 1> >(tee -a /workspace/logs/startup.log)
exec 2> >(tee -a /workspace/logs/startup.log >&2)

echo "Starting ComfyUI setup at $(date)"

# Create necessary directories
mkdir -p /workspace/ComfyUI/output
mkdir -p /workspace/logs

# Sync ComfyUI if needed
if [ -d "/ComfyUI" ]; then
    rsync -au --remove-source-files /ComfyUI/ /workspace/ComfyUI/
fi

# Link models if they exist
if [ -d "/comfy-models" ]; then
    ln -sf /comfy-models/* /workspace/ComfyUI/models/checkpoints/
fi

# Check CUDA and GPU availability
if ! command -v nvidia-smi &> /dev/null; then
    handle_error "NVIDIA driver not found"
fi

echo "CUDA Environment Check:"
nvidia-smi
echo "NVIDIA_VISIBLE_DEVICES: ${NVIDIA_VISIBLE_DEVICES}"
echo "CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES}"

# Verify PyTorch CUDA
python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA device count: {torch.cuda.device_count()}')" || handle_error "PyTorch CUDA check failed"

# Start ComfyUI
cd /workspace/ComfyUI || handle_error "Failed to change to ComfyUI directory"
python main.py --listen --port 8188 --enable-cors-header --verbose > /workspace/logs/comfyui.log 2>&1 &
COMFY_PID=$!
echo "ComfyUI started with PID: $COMFY_PID"

# Monitor ComfyUI process in background
(
while true; do
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        echo "ComfyUI crashed, checking logs:"
        tail -n 50 /workspace/logs/comfyui.log
        echo "Restarting ComfyUI..."
        cd /workspace/ComfyUI || handle_error "Failed to change to ComfyUI directory"
        python main.py --listen --port 8188 --enable-cors-header --verbose > /workspace/logs/comfyui.log 2>&1 &
        COMFY_PID=$!
        echo "ComfyUI restarted with PID: $COMFY_PID"
    fi
    sleep 10
done
) &

# Exit successfully to allow start.sh to continue
exit 0