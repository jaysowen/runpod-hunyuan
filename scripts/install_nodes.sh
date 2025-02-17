#!/bin/bash
set -e

CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
mkdir -p "$CUSTOM_NODES_DIR"
cd "$CUSTOM_NODES_DIR"

# Maximum number of parallel installations
MAX_PARALLEL=4
current_parallel=0

# Function to check if a repository needs to be updated
check_repo_status() {
    local repo_url=$1
    local dir_name=$(basename "$repo_url" .git)
    
    if [ -d "$dir_name" ]; then
        cd "$dir_name"
        
        # Fetch the latest changes without applying them
        git fetch origin > /dev/null 2>&1
        
        # Check if we're behind the remote
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})
        
        if [ $LOCAL = $REMOTE ]; then
            cd ..
            echo "skip" # Repository is up to date
        else
            cd ..
            echo "update" # Repository needs update
        fi
    else
        echo "install" # Repository needs installation
    fi
}

# Function to clone or update repository
clone_or_update() {
    local repo_url=$1
    local dir_name=$(basename "$repo_url" .git)
    local status=$(check_repo_status "$repo_url")
    
    case $status in
        "skip")
            echo "📦 $dir_name is up to date, skipping..."
            ;;
            
        "update")
            echo "🔄 Updating $dir_name..."
            cd "$dir_name"
            git pull
            if [ -f "requirements.txt" ]; then
                pip install --no-cache-dir -r requirements.txt
            fi
            if [ -f "install.py" ]; then
                python "install.py"
            fi
            cd ..
            echo "✅ Updated $dir_name successfully"
            ;;
            
        "install")
            echo "⬇️ Installing $dir_name..."
            git clone "$repo_url"
            if [ -f "$dir_name/requirements.txt" ]; then
                pip install --no-cache-dir -r "$dir_name/requirements.txt"
            fi
            if [ -f "$dir_name/install.py" ]; then
                python "$dir_name/install.py"
            fi
            echo "✅ Installed $dir_name successfully"
            ;;
    esac
}

# Function to process in parallel
process_parallel() {
    local repo_url=$1
    clone_or_update "$repo_url" &
    
    ((current_parallel++))
    
    if [ $current_parallel -ge $MAX_PARALLEL ]; then
        wait
        current_parallel=0
    fi
}

echo "🚀 Processing ComfyUI custom nodes..."

# Define arrays for different categories of nodes
declare -a VIDEO_NODES=(
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    "https://github.com/facok/ComfyUI-HunyuanVideoMultiLora.git"
)

declare -a WORKFLOW_NODES=(
    "https://github.com/Amorano/Jovimetrix.git"
    "https://github.com/sipherxyz/comfyui-art-venture.git"
    "https://github.com/theUpsider/ComfyUI-Logic.git"
    "https://github.com/Smirnov75/ComfyUI-mxToolkit.git"
    "https://github.com/alt-key-project/comfyui-dream-project.git"
)

declare -a ENHANCEMENT_NODES=(
    "https://github.com/Jonseed/ComfyUI-Detail-Daemon.git"
    "https://github.com/ShmuelRonen/ComfyUI-ImageMotionGuider.git"
    "https://github.com/BlenderNeko/ComfyUI_Noise.git"
    "https://github.com/chrisgoringe/cg-noisetools.git"
)

declare -a UTILITY_NODES=(
    "https://github.com/cubiq/ComfyUI_essentials.git"
    "https://github.com/chrisgoringe/cg-use-everywhere.git"
    "https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git"
    "https://github.com/ltdrdata/ComfyUI-Manager.git"
    "https://github.com/WASasquatch/was-node-suite-comfyui.git"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
)

declare -a SPECIAL_NODES=(
    "https://github.com/pharmapsychotic/comfy-cliption.git"
    "https://github.com/darkpixel/darkprompts.git"
    "https://github.com/Koushakur/ComfyUI-DenoiseChooser.git"
    "https://github.com/city96/ComfyUI-GGUF.git"
    "https://github.com/giriss/comfy-image-saver.git"
)

declare -a ADDITIONAL_NODES=(
    "https://github.com/11dogzi/Comfyui-ergouzi-Nodes.git"
    "https://github.com/jamesWalker55/comfyui-various.git"
    "https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git"
    "https://github.com/M1kep/ComfyLiterals.git"
    "https://github.com/welltop-cn/ComfyUI-TeaCache.git"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    "https://github.com/chengzeyi/Comfy-WaveSpeed.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
    "https://github.com/crystian/ComfyUI-Crystools.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/rgthree/rgthree-comfy.git"
)

# Process each category
echo "📽️ Processing Video Nodes..."
for repo in "${VIDEO_NODES[@]}"; do
    process_parallel "$repo"
done
wait
current_parallel=0

echo "🔧 Processing Workflow Nodes..."
for repo in "${WORKFLOW_NODES[@]}"; do
    process_parallel "$repo"
done
wait
current_parallel=0

echo "🎨 Processing Enhancement Nodes..."
for repo in "${ENHANCEMENT_NODES[@]}"; do
    process_parallel "$repo"
done
wait
current_parallel=0

echo "🛠️ Processing Utility Nodes..."
for repo in "${UTILITY_NODES[@]}"; do
    process_parallel "$repo"
done
wait
current_parallel=0

echo "🎯 Processing Special Purpose Nodes..."
for repo in "${SPECIAL_NODES[@]}"; do
    process_parallel "$repo"
done
wait
current_parallel=0

echo "➕ Processing Additional Nodes..."
for repo in "${ADDITIONAL_NODES[@]}"; do
    process_parallel "$repo"
done
wait

echo "✨ All custom nodes processing completed successfully"