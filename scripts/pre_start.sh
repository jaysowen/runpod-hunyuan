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

# --- Function to replace a workspace directory with a symlink to a volume directory ---
replace_with_symlink_from_volume() {
  local volume_source_dir="$1"    # e.g., /runpod-volume/ComfyUI/models/embeddings
  local workspace_target_dir="$2" # e.g., /workspace/ComfyUI/models/embeddings
  local model_name="$(basename "${workspace_target_dir}")"

  echo "Attempting to link ${model_name} models from volume..."

  # Ensure the parent directory for the workspace target exists (e.g. /workspace/ComfyUI/models)
  # This should already be created by the initial copy of /ComfyUI to /workspace/ComfyUI
  mkdir -p "$(dirname "${workspace_target_dir}")"

  # Check if the source directory exists on the volume
  if [ -d "${volume_source_dir}" ]; then
    # Remove the directory/symlink if it exists in the workspace (it would have been copied from original /ComfyUI)
    if [ -e "${workspace_target_dir}" ] || [ -L "${workspace_target_dir}" ]; then
      echo "Removing existing ${workspace_target_dir} before creating symlink to volume."
      rm -rf "${workspace_target_dir}"
    fi
    echo "Creating symlink for ${model_name}: ${workspace_target_dir} -> ${volume_source_dir}"
    ln -s "${volume_source_dir}" "${workspace_target_dir}"
  else
    echo "Warning: Source directory ${volume_source_dir} for ${model_name} not found on volume."
    echo "${model_name} will use the version from the base image, if it exists at ${workspace_target_dir}."
    # If it doesn't exist on volume, we leave whatever was copied from the original /ComfyUI/models/${model_name}
    # or if it wasn't in original image, it won't be in /workspace/ComfyUI/models/${model_name} either.
  fi
}

echo "PREPARING WORKSPACE AND COPYING BASE COMFYUI"
# Create /workspace/ComfyUI directory if it doesn't exist
mkdir -p /workspace/ComfyUI
chmod 755 /workspace/ComfyUI

# Check if /ComfyUI (original image content) exists and is not a symlink
if [ -d "/ComfyUI" ] && [ ! -L "/ComfyUI" ]; then
    echo "**** COPYING BASE COMFYUI FROM /ComfyUI TO /workspace/ComfyUI ****"
    # Copy contents of /ComfyUI (including hidden files) into /workspace/ComfyUI/
    # Using -a to preserve attributes and handle symlinks properly during copy.
    # The trailing /. ensures contents are copied into the target directory.
    cp -a /ComfyUI/. /workspace/ComfyUI/
else
    echo "/ComfyUI is already a symlink or does not exist as a directory. Skipping initial copy."
fi

echo "REPLACING MODEL DIRECTORIES IN WORKSPACE WITH SYMLINKS TO VOLUME"
# Call replace_with_symlink_from_volume for each model type
# These paths should match your volume structure and ComfyUI's expectations
replace_with_symlink_from_volume "/runpod-volume/ComfyUI/models/insightface" "/workspace/ComfyUI/models/insightface"
replace_with_symlink_from_volume "/runpod-volume/ComfyUI/models/ultralytics" "/workspace/ComfyUI/models/ultralytics"
replace_with_symlink_from_volume "/runpod-volume/ComfyUI/models/landmarks" "/workspace/ComfyUI/models/landmarks"
replace_with_symlink_from_volume "/runpod-volume/ComfyUI/models/sams" "/workspace/ComfyUI/models/sams"
replace_with_symlink_from_volume "/runpod-volume/ComfyUI/models/segformer_b3_clothes" "/workspace/ComfyUI/models/segformer_b3_clothes"
replace_with_symlink_from_volume "/runpod-volume/ComfyUI/models/grounding-dino" "/workspace/ComfyUI/models/grounding-dino"
replace_with_symlink_from_volume "/runpod-volume/ComfyUI/models/hyper_lora" "/workspace/ComfyUI/models/hyper_lora"
replace_with_symlink_from_volume "/runpod-volume/ComfyUI/models/embeddings" "/workspace/ComfyUI/models/embeddings"
# Add any other model types you need to link from the volume

echo "FINALIZING /ComfyUI SYMLINK TO POINT TO /workspace/ComfyUI"
# Remove original /ComfyUI directory if it exists and was copied from
if [ -d "/ComfyUI" ] && [ ! -L "/ComfyUI" ]; then
    echo "Removing original /ComfyUI directory after copy..."
    rm -rf /ComfyUI
fi

# Ensure /ComfyUI is a symlink to /workspace/ComfyUI
# Use -sfn to force symlink creation/update, even if /ComfyUI exists (as a symlink or file)
# -n (--no-dereference) is important if /ComfyUI itself could be a symlink, to replace the symlink itself.
echo "Ensuring /ComfyUI symlinks to /workspace/ComfyUI"
ln -sfn /workspace/ComfyUI /ComfyUI

# Ensure proper permissions on the final workspace content
chmod -R 755 /workspace/ComfyUI

echo "✨ Pre-start completed successfully ✨"
