#!/bin/bash
set -e

CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
mkdir -p "$CUSTOM_NODES_DIR"
cd "$CUSTOM_NODES_DIR"

# Function to clone if not exists
clone_if_not_exists() {
    local repo_url=$1
    local dir_name=$(basename "$repo_url" .git)
    
    if [ ! -d "$dir_name" ]; then
        echo "Installing $dir_name..."
        git clone "$repo_url"
        # Install requirements if they exist
        if [ -f "$dir_name/requirements.txt" ]; then
            pip install --no-cache-dir -r "$dir_name/requirements.txt"
        fi
        # Run install script if it exists
        if [ -f "$dir_name/install.py" ]; then
            python "$dir_name/install.py"
        fi
        echo "Installed $dir_name successfully"
    else
        echo "$dir_name already exists, skipping installation"
    fi
}

echo "Installing additional ComfyUI custom nodes..."

# Video and Frame Processing
clone_if_not_exists "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git"
clone_if_not_exists "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
clone_if_not_exists "https://github.com/facok/ComfyUI-HunyuanVideoMultiLora.git"

# Workflow Tools
clone_if_not_exists "https://github.com/Amorano/Jovimetrix.git"
clone_if_not_exists "https://github.com/sipherxyz/comfyui-art-venture.git"
clone_if_not_exists "https://github.com/theUpsider/ComfyUI-Logic.git"
clone_if_not_exists "https://github.com/Smirnov75/ComfyUI-mxToolkit.git"
clone_if_not_exists "https://github.com/alt-key-project/comfyui-dream-project.git"

# Image Enhancement
clone_if_not_exists "https://github.com/Jonseed/ComfyUI-Detail-Daemon.git"
clone_if_not_exists "https://github.com/ShmuelRonen/ComfyUI-ImageMotionGuider.git"

# Noise Tools
clone_if_not_exists "https://github.com/BlenderNeko/ComfyUI_Noise.git"
clone_if_not_exists "https://github.com/chrisgoringe/cg-noisetools.git"

# Utility Nodes
clone_if_not_exists "https://github.com/cubiq/ComfyUI_essentials.git"
clone_if_not_exists "https://github.com/chrisgoringe/cg-use-everywhere.git"
clone_if_not_exists "https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git"

# Special Purpose
clone_if_not_exists "https://github.com/pharmapsychotic/comfy-cliption.git"
clone_if_not_exists "https://github.com/darkpixel/darkprompts.git"
clone_if_not_exists "https://github.com/Koushakur/ComfyUI-DenoiseChooser.git"
clone_if_not_exists "https://github.com/city96/ComfyUI-GGUF.git"
clone_if_not_exists "https://github.com/giriss/comfy-image-saver.git"

# Additional Utilities
clone_if_not_exists "https://github.com/11dogzi/Comfyui-ergouzi-Nodes.git"
clone_if_not_exists "https://github.com/jamesWalker55/comfyui-various.git"
clone_if_not_exists "https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git"
clone_if_not_exists "https://github.com/M1kep/ComfyLiterals.git"
clone_if_not_exists "https://github.com/welltop-cn/ComfyUI-TeaCache.git"

clone_if_not_exists "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"

echo "All additional custom nodes installed successfully"