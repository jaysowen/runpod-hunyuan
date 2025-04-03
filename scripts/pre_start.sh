#!/bin/bash
set -e  # Exit on error

export PYTHONUNBUFFERED=1
export PATH="/workspace/bin:$PATH"

# Ensure workspace directory exists with proper permissions
mkdir -p /workspace
chmod 755 /workspace

# Check if models are already downloaded in the final workspace location
check_models_downloaded() {
    echo "🔍 Checking for existing models using download_models.sh --list-files..."
    # Get the list of required model files directly from the download script
    # Use process substitution and mapfile to read paths into an array
    mapfile -t required_models < <( /download_models.sh --list-files || echo "Error getting model list" >&2 )

    # Check if mapfile failed (e.g., download_models.sh exited with error)
    if [ ${#required_models[@]} -eq 0 ] || [[ "${required_models[0]}" == "Error getting model list" ]]; then
        echo "❌ Failed to retrieve model list from /download_models.sh. Assuming models are not downloaded." >&2
        return 1 # Indicate models are not downloaded or list is unavailable
    fi

    echo "Expected models in workspace:"
    printf "  - %s\n" "${required_models[@]}"

    local missing_or_empty=false
    for model_path in "${required_models[@]}"; do
        if [ ! -f "$model_path" ]; then
            echo "    ❓ Missing: $(basename "$model_path")"
            missing_or_empty=true
        elif [ ! -s "$model_path" ]; then
            echo "    ❓ Empty: $(basename "$model_path")"
            missing_or_empty=true
        fi
        # No need for an 'else' clause, we only care about missing/empty files
    done

    if [ "$missing_or_empty" = true ]; then
        echo "↳ Some models are missing or empty in the workspace."
        return 1 # Indicate models need downloading/verification
    else
        echo "↳ All expected models found and are not empty in the workspace."
        return 0 # Indicate models are present
    fi
}

echo "**** CHECK NODES AND INSTALL IF NOT FOUND ****"
if [ "${SKIP_NODES}" == "true" ]; then
    echo "**** SKIPPING NODE INSTALLATION (SKIP_NODES=true) ****"
else
    /install_nodes.sh install_only
fi

# Check if downloads should be skipped
if [ "${SKIP_DOWNLOADS}" == "true" ]; then
    echo "**** SKIPPING MODEL DOWNLOADS (SKIP_DOWNLOADS=true) ****"
elif check_models_downloaded; then
    echo "**** MODELS ALREADY DOWNLOADED, SKIPPING DOWNLOAD ****"
else
    echo "**** DOWNLOADING - INSTALLING MODELS ****"
    /download_models.sh
fi

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
