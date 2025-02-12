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

# Function to install additional nodes
install_additional_nodes() {
    echo "Installing additional custom nodes..."
    cd /workspace/ComfyUI/custom_nodes || return 1
    
    # Clone core custom nodes
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git
    git clone https://github.com/BlenderNeko/ComfyUI_Noise.git
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git

    # Clone utility nodes
    git clone https://github.com/chrisgoringe/cg-noisetools.git
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
    git clone https://github.com/kijai/ComfyUI-KJNodes.git

    # Clone enhancement nodes
    git clone https://github.com/Jonseed/ComfyUI-Detail-Daemon.git
    git clone https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git
    git clone https://github.com/chengzeyi/Comfy-WaveSpeed.git

    # Clone workflow nodes
    git clone https://github.com/Amorano/Jovimetrix.git
    git clone https://github.com/sipherxyz/comfyui-art-venture.git
    git clone https://github.com/theUpsider/ComfyUI-Logic.git
    git clone https://github.com/Smirnov75/ComfyUI-mxToolkit.git
    git clone https://github.com/alt-key-project/comfyui-dream-project.git

    # Clone special purpose nodes
    git clone https://github.com/pharmapsychotic/comfy-cliption.git
    git clone https://github.com/darkpixel/darkprompts.git
    git clone https://github.com/Koushakur/ComfyUI-DenoiseChooser.git
    git clone https://github.com/giriss/comfy-image-saver.git
    git clone https://github.com/facok/ComfyUI-HunyuanVideoMultiLora.git
    git clone https://github.com/11dogzi/Comfyui-ergouzi-Nodes.git
    git clone https://github.com/jamesWalker55/comfyui-various.git
    git clone https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git
    git clone https://github.com/ShmuelRonen/ComfyUI-ImageMotionGuider.git
    git clone https://github.com/M1kep/ComfyLiterals.git
    git clone https://github.com/welltop-cn/ComfyUI-TeaCache.git

    # Install requirements for all new custom nodes
    cd /workspace/ComfyUI || return 1
    find custom_nodes -name requirements.txt -exec pip install -r {} \;
    
    echo "Additional custom nodes installation completed."
}

# Function to wait for DNS resolution
wait_for_dns() {
    local max_attempts=30
    local attempt=1
    
    echo "Waiting for DNS resolution..."
    while ! nslookup huggingface.co >/dev/null 2>&1; do
        if [ $attempt -ge $max_attempts ]; then
            echo "DNS resolution failed after $max_attempts attempts"
            return 1
        fi
        echo "Attempt $attempt: DNS not ready, waiting 5 seconds..."
        sleep 5
        attempt=$((attempt + 1))
    done
    echo "DNS resolution successful"
    return 0
}

# Function to download models if they don't exist
download_models() {
    echo "Checking and downloading required models..."
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if wait_for_dns; then
            # Create directories if they don't exist
            mkdir -p /workspace/ComfyUI/models/{text_encoders,vae,clip_vision,unet,loras,upscale}
            
            # Download UNET model
            if [ ! -f /workspace/ComfyUI/models/unet/hunyuan_video_720_cfgdistill_bf16.safetensors ]; then
                echo "Downloading hunyuan_video_720_cfgdistill_bf16.safetensors..."
                wget -O /workspace/ComfyUI/models/unet/hunyuan_video_720_cfgdistill_bf16.safetensors \
                    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors"
            fi

            # Download text encoder models
            if [ ! -f /workspace/ComfyUI/models/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors ]; then
                echo "Downloading Long-ViT-L-14-GmP-SAE-TE-only.safetensors..."
                wget -O /workspace/ComfyUI/models/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors \
                    "https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"
            fi

            if [ ! -f /workspace/ComfyUI/models/text_encoders/llava_llama3_fp8_scaled.safetensors ]; then
                echo "Downloading llava_llama3_fp8_scaled.safetensors..."
                wget -O /workspace/ComfyUI/models/text_encoders/llava_llama3_fp8_scaled.safetensors \
                    "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors"
            fi

            # Download VAE model
            if [ ! -f /workspace/ComfyUI/models/vae/hunyuan_video_vae_bf16.safetensors ]; then
                echo "Downloading hunyuan_video_vae_bf16.safetensors..."
                wget -O /workspace/ComfyUI/models/vae/hunyuan_video_vae_bf16.safetensors \
                    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors"
            fi

            # Download CLIP vision model
            if [ ! -f /workspace/ComfyUI/models/clip_vision/clip-vit-large-patch14.safetensors ]; then
                echo "Downloading clip-vit-large-patch14.safetensors..."
                wget -O /workspace/ComfyUI/models/clip_vision/clip-vit-large-patch14.safetensors \
                    "https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors"
            fi

            if [ ! -f /workspace/ComfyUI/models/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors ]; then
                echo "Downloading hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors..."
                wget -O /workspace/ComfyUI/models/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors \
                    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"
            fi

            # Optional/Additional Models (commented out)
            # # Download additional UNET model
            # if [ ! -f /workspace/ComfyUI/models/unet/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensors ]; then
            #     echo "Downloading hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensors..."
            #     wget -O /workspace/ComfyUI/models/unet/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensors \
            #         "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensor"
            # fi

            # # Download LoRA models
            # if [ ! -f /workspace/ComfyUI/models/loras/img2vid.safetensors ]; then
            #     echo "Downloading img2vid.safetensors..."
            #     wget -O /workspace/ComfyUI/models/loras/img2vid.safetensors \
            #         "https://huggingface.co/leapfusion-image2vid-test/image2vid-512x320/resolve/main/img2vid.safetensors"
            # fi


            
            echo "Model downloads completed."
            return 0
        fi
        
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            echo "Download attempt $retry failed. Retrying in 10 seconds..."
            sleep 10
        fi
    done
    
    echo "Failed to download models after $max_retries attempts"
    return 1
}

# Set up logging
exec 1> >(tee -a /workspace/startup.log)
exec 2> >(tee -a /workspace/startup.log >&2)

echo "Starting services at $(date)"

# Create necessary directories
mkdir -p /workspace/ComfyUI/output || handle_error "Failed to create output directory"
mkdir -p /workspace/logs || handle_error "Failed to create logs directory"

# Install additional DNS tools if needed
apt-get update && apt-get install -y dnsutils

# Download models if needed
if ! download_models; then
    echo "WARNING: Initial model download failed. Continuing startup..."
    echo "You can manually run /workspace/download-fix.sh once the container is running"
fi

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