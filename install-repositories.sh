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

# Set up logging
exec 1> >(tee -a /workspace/startup.log)
exec 2> >(tee -a /workspace/startup.log >&2)

echo "Starting services at $(date)"

# Create necessary directories
mkdir -p /workspace/ComfyUI/output || handle_error "Failed to create output directory"
mkdir -p /workspace/logs || handle_error "Failed to create logs directory"

# Function to download a model if it doesn't exist
download_model() {
    local directory=$1
    local filename=$2
    local url=$3
    
    if [ ! -f "$directory/$filename" ]; then
        echo "Downloading $filename..."
        wget -O "$directory/$filename" "$url" || {
            echo "Failed to download $filename"
            return 1
        }
    else
        echo "$filename already exists, skipping download"
    fi
}

# Create directory structure
mkdir -p /workspace/ComfyUI/models/{unet,text_encoders,vae,upscale,loras}
mkdir -p /workspace/ComfyUI/custom_nodes
mkdir -p /workspace/ComfyUI/user/default/workflows

# Set base paths
MODELS_DIR="/workspace/ComfyUI/models"
UNET_DIR="$MODELS_DIR/unet"
VAE_DIR="$MODELS_DIR/vae"
UPSCALE_DIR="$MODELS_DIR/upscale"
TEXT_ENCODERS_DIR="$MODELS_DIR/text_encoders"
LORA_DIR="$MODELS_DIR/loras"

# Download models
echo "Starting model downloads..."

# UNet models
download_model "$UNET_DIR" \
    "hunyuan_video_720_cfgdistill_bf16.safetensors" \
    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors"

download_model "$UNET_DIR" \
    "hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors" \
    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"

# LoRA models
download_model "$LORA_DIR" \
    "hyvideo_FastVideo_LoRA-fp8.safetensors" \
    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hyvideo_FastVideo_LoRA-fp8.safetensors"

# VAE models
download_model "$VAE_DIR" \
    "img2vid.safetensors" \
    "https://huggingface.co/leapfusion-image2vid-test/image2vid-512x320/resolve/main/img2vid.safetensors"

download_model "$VAE_DIR" \
    "hunyuan_video_vae_bf16.safetensors" \
    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors"

# Upscaler model
download_model "$UPSCALE_DIR" \
    "4x_foolhardy_Remacri.pth" \
    "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth"

# Text encoder models
download_model "$TEXT_ENCODERS_DIR" \
    "clip_l.safetensors" \
    "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/clip_l.safetensors"

download_model "$TEXT_ENCODERS_DIR" \
    "llava_llama3_fp8_scaled.safetensors" \
    "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors"

echo "Model downloads completed"

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