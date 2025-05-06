#!/bin/bash
set -e  # Exit on error

export PYTHONUNBUFFERED=1
export PATH="/workspace/bin:$PATH"

# Ensure workspace directory exists with proper permissions
mkdir -p /workspace
chmod 755 /workspace

# --- Model Check and Download Logic Removed --- 
# Models are now expected to be mounted via a network volume
# and configured in src/extra_model_paths.yaml

# --- Node Installation Call Removed ---
# Custom nodes are cloned and their requirements installed during Docker build.
# No node installation/update is expected during startup.

# --- Function to create model symlinks ---
create_model_symlink() {
  local source_dir="$1"
  local target_dir="$2"
  local model_name="$(basename "${target_dir}")"

  echo "Checking symlink for ${model_name} models..."

  # Ensure the parent directory for the target exists
  mkdir -p "$(dirname "${target_dir}")"

  # Check if the source directory exists on the volume
  if [ -d "${source_dir}" ]; then
    # Check if the target path doesn't exist or is not already a symlink
    if [ ! -e "${target_dir}" ] && [ ! -L "${target_dir}" ]; then
      echo "Creating symlink for ${model_name}: ${target_dir} -> ${source_dir}"
      ln -s "${source_dir}" "${target_dir}"
    elif [ -L "${target_dir}" ]; then
       echo "Symlink ${target_dir} already exists."
    else
       echo "Warning: ${target_dir} exists but is not a symlink. Cannot create link for ${model_name}."
    fi
  else
    echo "Warning: Source directory ${source_dir} not found on volume. Cannot create symlink for ${model_name}."
  fi
}

# --- Create Symlinks using the function ---
create_model_symlink "/runpod-volume/ComfyUI/models/insightface" "/workspace/ComfyUI/models/insightface"
create_model_symlink "/runpod-volume/ComfyUI/models/ultralytics" "/workspace/ComfyUI/models/ultralytics"
create_model_symlink "/runpod-volume/ComfyUI/models/landmarks" "/workspace/ComfyUI/models/landmarks"
create_model_symlink "/runpod-volume/ComfyUI/models/sams" "/workspace/ComfyUI/models/sams"
create_model_symlink "/runpod-volume/ComfyUI/models/segformer_b3_clothes" "/workspace/ComfyUI/models/segformer_b3_clothes"
create_model_symlink "/runpod-volume/ComfyUI/models/grounding-dino" "/workspace/ComfyUI/models/grounding-dino"

# --- End Symlink Creation ---

echo "MOVING COMFYUI TO WORKSPACE"
# Ensure clean workspace/ComfyUI directory setup
if [ -e "/workspace/ComfyUI" ]; then
    if [ ! -d "/workspace/ComfyUI" ]; then
        echo "Removing invalid /workspace/ComfyUI"
        rm -f /workspace/ComfyUI
    fi
fi

# Create fresh ComfyUI directory
mkdir -p /workspace/ComfyUI
chmod 755 /workspace/ComfyUI

# Check if /ComfyUI exists and is not already a symlink
if [ -d "/ComfyUI" ] && [ ! -L "/ComfyUI" ]; then
    echo "**** SETTING UP COMFYUI IN WORKSPACE ****"
    # Copy files instead of moving to avoid potential issues
    cp -rf /ComfyUI/* /workspace/ComfyUI/
    cp -rf /ComfyUI/.??* /workspace/ComfyUI/ 2>/dev/null || true
    rm -rf /ComfyUI
    # Create symlink
    ln -sf /workspace/ComfyUI /ComfyUI
fi

# Ensure proper permissions
chmod -R 755 /workspace/ComfyUI

echo "✨ Pre-start completed successfully ✨"
