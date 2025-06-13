#!/bin/bash
set -e  # Exit the script if any statement returns a non-true return value

echo "Pod Started"

# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #

echo "Running pre-start script (if exists)..."
if [[ -f "/pre_start.sh" ]]; then
    bash "/pre_start.sh"
else
    echo "No pre_start.sh found."
fi

# Force update for ComfyUI-KJNodes to fix runtime errors
echo "Force updating ComfyUI-KJNodes to ensure latest bug fixes..."
if [ -d "/ComfyUI/custom_nodes/ComfyUI-KJNodes" ]; then
    rm -rf /ComfyUI/custom_nodes/ComfyUI-KJNodes
fi
git clone https://github.com/kijai/ComfyUI-KJNodes.git /ComfyUI/custom_nodes/ComfyUI-KJNodes
echo "ComfyUI-KJNodes updated."

echo "Running post-start script (if exists)..."
if [[ -f "/post_start.sh" ]]; then
    bash "/post_start.sh"
else
    echo "No post_start.sh found."
fi

echo "Start script(s) finished, serverless is ready to use."

# Keep the container running indefinitely, the actual work is done by processes
# started in post_start.sh (usually the RunPod handler)
sleep infinity
