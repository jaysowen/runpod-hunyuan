#!/bin/bash

# Clone ComfyUI base if it doesn't exist
if [ ! -d "ComfyUI" ]; then
    echo 'WTF COMFYUI NOT INSTALLED'
fi

# Create model directories and download models
cd /workspace/ComfyUI
mkdir -p models/{unet,text_encoders,vae,clip_vision,loras}

# Download models
wget -O models/unet/hunyuan_video_720_cfgdistill_bf16.safetensors \
    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors"

wget -O models/text_encoders/Long-ViT-L-14-GmP-SAE-TE-only.safetensors \
    "https://huggingface.co/zer0int/LongCLIP-SAE-ViT-L-14/resolve/main/Long-ViT-L-14-GmP-SAE-TE-only.safetensors"

wget -O models/text_encoders/llava_llama3_fp8_scaled.safetensors \
    "https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors"

wget -O models/vae/hunyuan_video_vae_bf16.safetensors \
    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors"

wget -O models/clip_vision/clip-vit-large-patch14.safetensors \
    "https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors"

wget -O models/loras/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors \
    "https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors"

# Create and enter custom_nodes directory
cd /workspace/ComfyUI
mkdir -p custom_nodes
cd custom_nodes

# Utility nodes
git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git
git clone https://github.com/BlenderNeko/ComfyUI_Noise.git
git clone https://github.com/chrisgoringe/cg-noisetools.git
git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
git clone https://github.com/cubiq/ComfyUI_essentials.git
git clone https://github.com/chrisgoringe/cg-use-everywhere.git
git clone https://github.com/Jonseed/ComfyUI-Detail-Daemon.git
git clone https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git

# Workflow nodes
git clone https://github.com/Amorano/Jovimetrix.git
git clone https://github.com/sipherxyz/comfyui-art-venture.git
git clone https://github.com/theUpsider/ComfyUI-Logic.git
git clone https://github.com/Smirnov75/ComfyUI-mxToolkit.git
git clone https://github.com/alt-key-project/comfyui-dream-project.git

# Special purpose nodes
git clone https://github.com/pharmapsychotic/comfy-cliption.git
git clone https://github.com/darkpixel/darkprompts.git
git clone https://github.com/Koushakur/ComfyUI-DenoiseChooser.git
git clone https://github.com/city96/ComfyUI-GGUF.git
git clone https://github.com/giriss/comfy-image-saver.git

# Additional nodes
git clone https://github.com/facok/ComfyUI-HunyuanVideoMultiLora.git
git clone https://github.com/11dogzi/Comfyui-ergouzi-Nodes.git
git clone https://github.com/jamesWalker55/comfyui-various.git
git clone https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git
git clone https://github.com/ShmuelRonen/ComfyUI-ImageMotionGuider.git
git clone https://github.com/M1kep/ComfyLiterals.git
git clone https://github.com/welltop-cn/ComfyUI-TeaCache.git

# Install dependencies for each custom node
for d in */ ; do
    if [ -f "${d}requirements.txt" ]; then
        cd "$d"
        pip install -r requirements.txt || true
        cd ..
    fi
done