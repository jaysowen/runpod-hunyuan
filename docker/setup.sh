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
if [ ! -f /workspace/ComfyUI/AllinOne1.4.json ]; then
    cp /workspace/AllinOne1.4.json /workspace/ComfyUI/user/default/workflows/AllinOne1.4.json
fi
" >> /workspace/start.sh

cd /workspace/ComfyUI