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
        echo "INSTALLING --  $dir_name..."
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
clone_if_not_exists "https://github.com/facok/ComfyUI-HunyuanVideoMultiLora.git"
clone_if_not_exists "https://github.com/cubiq/ComfyUI_essentials.git"
clone_if_not_exists "https://github.com/chrisgoringe/cg-use-everywhere.git"
clone_if_not_exists "https://github.com/city96/ComfyUI-GGUF.git"
clone_if_not_exists "https://github.com/welltop-cn/ComfyUI-TeaCache.git"
clone_if_not_exists "https://github.com/ltdrdata/ComfyUI-Manager.git"
clone_if_not_exists "https://github.com/yolain/ComfyUI-Easy-Use.git"
clone_if_not_exists "https://github.com/crystian/ComfyUI-Crystools.git"
clone_if_not_exists "https://github.com/kijai/ComfyUI-KJNodes.git"
clone_if_not_exists "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
clone_if_not_exists "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
clone_if_not_exists "https://github.com/rgthree/rgthree-comfy.git"
clone_if_not_exists "https://github.com/WASasquatch/was-node-suite-comfyui.git"

echo "All additional custom nodes installed successfully"