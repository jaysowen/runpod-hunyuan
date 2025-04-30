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

# --- Create Symlinks for models expected in default paths ---
echo "Creating model symlinks if necessary..."
# Ensure the default models directory exists
mkdir -p /workspace/ComfyUI/models

# Path where the model *actually* exists on the mounted volume
SEGFORMER_SOURCE_PATH="/runpod-volume/models/segformer_b3_clothes"
# Path where the node *expects* the model to be
SEGFORMER_TARGET_PATH="/workspace/ComfyUI/models/segformer_b3_clothes"

# Check if the source directory exists on the volume
if [ -d "${SEGFORMER_SOURCE_PATH}" ]; then
  # Check if the target path doesn't exist or is not already a symlink
  if [ ! -e "${SEGFORMER_TARGET_PATH}" ] && [ ! -L "${SEGFORMER_TARGET_PATH}" ]; then
    echo "Creating symlink for segformer_b3_clothes: ${SEGFORMER_TARGET_PATH} -> ${SEGFORMER_SOURCE_PATH}"
    ln -s "${SEGFORMER_SOURCE_PATH}" "${SEGFORMER_TARGET_PATH}"
  elif [ -L "${SEGFORMER_TARGET_PATH}" ]; then
     echo "Symlink ${SEGFORMER_TARGET_PATH} already exists."
  else
     echo "Warning: ${SEGFORMER_TARGET_PATH} exists but is not a symlink. Cannot create link."
  fi
else
  echo "Warning: Source directory ${SEGFORMER_SOURCE_PATH} not found on volume. Cannot create symlink."
fi
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
