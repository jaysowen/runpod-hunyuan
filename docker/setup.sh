#!/bin/bash

# Create directory structure
mkdir -p /workspace/ComfyUI/models/{diffusion_models,text_encoders,vae,upscale,loras}
mkdir -p /workspace/ComfyUI/custom_nodes
mkdir -p /workspace/ComfyUI/user/default/workflows

# Add to the startup script to ensure models are in place
echo "
# Check and create required directories
mkdir -p /workspace/ComfyUI/models/{diffusion_models,text_encoders,vae,upscale,loras}

# Ensure workflow is in place
if [ ! -f /workspace/ComfyUI/workflow.json ]; then
    cp /workspace/workflow.json /workspace/ComfyUI/workflow.json
fi
" >> /workspace/start.sh

# Download required model files
cd /workspace/ComfyUI/models

# Download additional required models
cd upscale
wget -O 4x_foolhardy_Remacri.pth https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth

# Install additional Python packages if needed
cd /workspace/ComfyUI