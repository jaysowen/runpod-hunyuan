#!/bin/bash

# Create directory structure
mkdir -p /workspace/ComfyUI/models/{diffusion_models,text_encoders,vae,upscale,loras}
mkdir -p /workspace/ComfyUI/custom_nodes
mkdir -p /workspace/ComfyUI/user/default/workflows

# Add to the startup script to ensure directories are in place
echo "
# Check and create required directories
mkdir -p /workspace/ComfyUI/models/{diffusion_models,text_encoders,vae,upscale,loras}

# Ensure workflow is in place
if [ ! -f /workspace/ComfyUI/AllinOneUltra1.2.json ]; then
    cp /workspace/AllinOneUltra1.2.json /workspace/ComfyUI/user/default/workflows/AllinOneUltra1.2.json
fi
# Ensure download-fix.sh is in place
if [ ! -f /workspace/download-fix.sh ]; then
    cp /download-fix.sh /workspace/download-fix.sh
    chmod +x /workspace/download-fix.sh
fi
" >> /workspace/start.sh


cd /workspace/ComfyUI