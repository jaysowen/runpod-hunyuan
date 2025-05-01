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

# --- Symlink creation logic removed ---

# --- Create Symlink for InsightFace models ---
echo "Creating symlink for InsightFace models if necessary..."

INSIGHTFACE_SOURCE_DIR="/runpod-volume/ComfyUI/models/insightface"
INSIGHTFACE_TARGET_DIR="/workspace/ComfyUI/models/insightface"

# Ensure the parent directory for the target exists
mkdir -p /workspace/ComfyUI/models

# Check if the source directory exists on the volume
if [ -d "${INSIGHTFACE_SOURCE_DIR}" ]; then
  # Check if the target path doesn't exist or is not already a symlink
  if [ ! -e "${INSIGHTFACE_TARGET_DIR}" ] && [ ! -L "${INSIGHTFACE_TARGET_DIR}" ]; then
    echo "Creating symlink for InsightFace: ${INSIGHTFACE_TARGET_DIR} -> ${INSIGHTFACE_SOURCE_DIR}"
    ln -s "${INSIGHTFACE_SOURCE_DIR}" "${INSIGHTFACE_TARGET_DIR}"
  elif [ -L "${INSIGHTFACE_TARGET_DIR}" ]; then
     echo "Symlink ${INSIGHTFACE_TARGET_DIR} already exists."
  else
     echo "Warning: ${INSIGHTFACE_TARGET_DIR} exists but is not a symlink. Cannot create link."
  fi
else
  echo "Warning: Source directory ${INSIGHTFACE_SOURCE_DIR} not found on volume. Cannot create symlink."
fi
# --- End InsightFace Symlink Creation ---

# --- Create Symlink for Ultralytics models ---
echo "Creating symlink for Ultralytics models if necessary..."

ULTRALYTICS_SOURCE_DIR="/runpod-volume/ComfyUI/models/ultralytics"
ULTRALYTICS_TARGET_DIR="/workspace/ComfyUI/models/ultralytics"

# Ensure the parent directory for the target exists
mkdir -p /workspace/ComfyUI/models

# Check if the source directory exists on the volume
if [ -d "${ULTRALYTICS_SOURCE_DIR}" ]; then
  # Check if the target path doesn't exist or is not already a symlink
  if [ ! -e "${ULTRALYTICS_TARGET_DIR}" ] && [ ! -L "${ULTRALYTICS_TARGET_DIR}" ]; then
    echo "Creating symlink for Ultralytics: ${ULTRALYTICS_TARGET_DIR} -> ${ULTRALYTICS_SOURCE_DIR}"
    ln -s "${ULTRALYTICS_SOURCE_DIR}" "${ULTRALYTICS_TARGET_DIR}"
  elif [ -L "${ULTRALYTICS_TARGET_DIR}" ]; then
     echo "Symlink ${ULTRALYTICS_TARGET_DIR} already exists."
  else
     echo "Warning: ${ULTRALYTICS_TARGET_DIR} exists but is not a symlink. Cannot create link."
  fi
else
  echo "Warning: Source directory ${ULTRALYTICS_SOURCE_DIR} not found on volume. Cannot create symlink."
fi
# --- End Ultralytics Symlink Creation ---

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
