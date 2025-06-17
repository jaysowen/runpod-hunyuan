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

# --- Function to create model symlinks with waiting ---
create_model_symlink() {
  local source_dir="$1"
  local target_dir="$2"
  local model_name="$(basename "${target_dir}")"

  echo "Mapping model: ${model_name}"

  # Wait for the source directory to become available from the network volume.
  echo "  - Waiting for source: ${source_dir}"
  local max_wait=120
  local waited=0
  while [ ! -d "${source_dir}" ]; do
      if [ $waited -ge $max_wait ]; then
          echo "Error: Timed out waiting for source directory ${source_dir}." >&2
          echo "  - Please ensure the model is correctly placed on your network volume." >&2
          exit 1
      fi
      sleep 5
      waited=$((waited + 5))
  done
  echo "  - Source directory found."

  # Ensure the parent directory for the target exists
  mkdir -p "$(dirname "${target_dir}")"

  # Create the symlink if the target path doesn't exist or is a broken link
  if [ -L "${target_dir}" ] && [ ! -e "${target_dir}" ]; then
      echo "  - Removing broken symlink at ${target_dir}."
      rm "${target_dir}"
  fi
  
  if [ -e "${target_dir}" ]; then
      echo "  - Target path ${target_dir} already exists. Skipping."
  else
      echo "  - Creating symlink: ${target_dir} -> ${source_dir}"
      ln -s "${source_dir}" "${target_dir}"
      echo "  - Symlink created successfully."
  fi
}

# --- Create Symlinks using the function ---
SOURCE_BASE="/runpod-volume/ComfyUI/models"
TARGET_BASE="/workspace/ComfyUI/models"

create_model_symlink "${SOURCE_BASE}/insightface" "${TARGET_BASE}/insightface"
create_model_symlink "${SOURCE_BASE}/ultralytics" "${TARGET_BASE}/ultralytics"
create_model_symlink "${SOURCE_BASE}/landmarks" "${TARGET_BASE}/landmarks"
create_model_symlink "${SOURCE_BASE}/sams" "${TARGET_BASE}/sams"
create_model_symlink "${SOURCE_BASE}/sams2" "${TARGET_BASE}/sams2"
create_model_symlink "${SOURCE_BASE}/segformer_b3_clothes" "${TARGET_BASE}/segformer_b3_clothes"
create_model_symlink "${SOURCE_BASE}/grounding-dino" "${TARGET_BASE}/grounding-dino"
create_model_symlink "${SOURCE_BASE}/vitmatte" "${TARGET_BASE}/vitmatte"
create_model_symlink "${SOURCE_BASE}/bert-base-uncased" "${TARGET_BASE}/bert-base-uncased"
create_model_symlink "${SOURCE_BASE}/jonathandinu--face-parsing" "${TARGET_BASE}/jonathandinu--face-parsing"
create_model_symlink "${SOURCE_BASE}/bisenet" "${TARGET_BASE}/bisenet"
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
