#!/bin/bash

# Function to handle errors
handle_error() {
    echo "Error: $1"
    if [ -f /workspace/logs/comfyui.log ]; then
        echo "ComfyUI Log Output:"
        cat /workspace/logs/comfyui.log
    fi
    exit 1
}

# Function to download models if they don't exist
download_models() {
    echo "Checking and downloading required models..."
    
    # Create directories if they don't exist
    mkdir -p /workspace/ComfyUI/models/{diffusion_models,text_encoders,vae,upscale}
    
    # Download HunyuanVideo models if they don't exist
    if [ ! -f /workspace/ComfyUI/models/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensors ]; then
        echo "Downloading hunyuan_video_t2v_720p_bf16.safetensors..."
        wget -O /workspace/ComfyUI/models/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensors \
            "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensors?download=true"
    fi

    if [ ! -f /workspace/ComfyUI/models/text_encoders/clip_l.safetensors ]; then
        echo "Downloading clip_l.safetensors..."
        wget -O /workspace/ComfyUI/models/text_encoders/clip_l.safetensors \
            "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/clip_l.safetensors?download=true"
    fi

    if [ ! -f /workspace/ComfyUI/models/text_encoders/llava_llama3_fp8_scaled.safetensors ]; then
        echo "Downloading llava_llama3_fp8_scaled.safetensors..."
        wget -O /workspace/ComfyUI/models/text_encoders/llava_llama3_fp8_scaled.safetensors \
            "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors?download=true"
    fi

    if [ ! -f /workspace/ComfyUI/models/vae/hunyuan_video_vae_bf16.safetensors ]; then
        echo "Downloading hunyuan_video_vae_bf16.safetensors..."
        wget -O /workspace/ComfyUI/models/vae/hunyuan_video_vae_bf16.safetensors \
            "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/vae/hunyuan_video_vae_bf16.safetensors?download=true"
    fi

    # Download upscaler model if it doesn't exist
    if [ ! -f /workspace/ComfyUI/models/upscale/4x_foolhardy_Remacri.pth ]; then
        echo "Downloading 4x_foolhardy_Remacri.pth..."
        wget -O /workspace/ComfyUI/models/upscale/4x_foolhardy_Remacri.pth \
            "https://huggingface.co/datasets/FacehugmansPics/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth"
    fi
}

# Set up logging
exec 1> >(tee -a /workspace/startup.log)
exec 2> >(tee -a /workspace/startup.log >&2)

echo "Starting services at $(date)"

# Create necessary directories
mkdir -p /workspace/ComfyUI/output || handle_error "Failed to create output directory"
mkdir -p /workspace/logs || handle_error "Failed to create logs directory"

# Download models if needed
download_models

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

# Activate virtual environment
source /opt/venv/bin/activate || handle_error "Failed to activate virtual environment"

# Check NVIDIA driver and CUDA
if ! command -v nvidia-smi &> /dev/null; then
    handle_error "NVIDIA driver not found"
fi

echo "CUDA Environment Check:"
nvidia-smi
echo "NVIDIA_VISIBLE_DEVICES: ${NVIDIA_VISIBLE_DEVICES}"
echo "CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES}"

# Verify PyTorch CUDA availability
python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA device count: {torch.cuda.device_count()}')" || handle_error "PyTorch CUDA check failed"

# Start ComfyUI
python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header --verbose > /workspace/logs/comfyui.log 2>&1 &
COMFY_PID=$!
echo "ComfyUI started with PID: $COMFY_PID"

# Monitor processes
while true; do
    if ! kill -0 $VSCODE_PID 2>/dev/null; then
        echo "VS Code server crashed, restarting..."
        code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/logs/vscode.log 2>&1 &
        VSCODE_PID=$!
    fi
    
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        echo "ComfyUI crashed, checking logs:"
        tail -n 50 /workspace/logs/comfyui.log
        echo "Restarting ComfyUI..."
        cd /workspace/ComfyUI
        python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header --verbose > /workspace/logs/comfyui.log 2>&1 &
        COMFY_PID=$!
    fi
    
    sleep 10
done