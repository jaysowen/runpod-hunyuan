#!/bin/bash
set -e

# Exit immediately if SKIP_NODES is set to true and we're not forcing installation
if [ "${SKIP_NODES}" == "true" ] && [ "$1" != "force" ]; then
    echo "SKIP_NODES is set to true, skipping node installations"
    exit 0
fi

CUSTOM_NODES_DIR="/ComfyUI/custom_nodes"
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

# Install only the specified nodes
clone_if_not_exists "https://github.com/chrisgoringe/cg-use-everywhere.git"
clone_if_not_exists "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git" 
clone_if_not_exists "https://github.com/crystian/ComfyUI-Crystools.git"
clone_if_not_exists "https://github.com/kijai/ComfyUI-KJNodes.git"
clone_if_not_exists "https://github.com/rgthree/rgthree-comfy.git"
clone_if_not_exists "https://github.com/WASasquatch/was-node-suite-comfyui.git"
clone_if_not_exists "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
clone_if_not_exists "https://github.com/yolain/ComfyUI-Easy-Use.git"
clone_if_not_exists "https://github.com/cubiq/ComfyUI_essentials"
clone_if_not_exists "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
clone_if_not_exists "https://github.com/chflame163/ComfyUI_LayerStyle.git"
clone_if_not_exists "https://github.com/kijai/ComfyUI-Florence2.git"
clone_if_not_exists "https://github.com/kijai/ComfyUI-segment-anything-2.git"
clone_if_not_exists "https://github.com/storyicon/comfyui_segment_anything.git"
clone_if_not_exists "https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git"
clone_if_not_exists "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"

echo "✨ Install Nodes completed successfully ✨"