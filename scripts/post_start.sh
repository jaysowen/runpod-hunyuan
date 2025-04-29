#!/bin/bash
set -e  # Exit on error

# Ensure we're starting in a valid directory
cd /

# --- File copying logic removed --- 
# download-files.sh and files.txt are no longer used as downloads are disabled post-start.

echo "⭐⭐⭐⭐⭐   ALL DONE - STARTING COMFYUI ⭐⭐⭐⭐⭐"

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Change to ComfyUI directory
cd /workspace/ComfyUI

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "runpod-worker-comfy: Starting ComfyUI"
    python3 main.py --disable-auto-launch --disable-metadata --listen
else
    echo "runpod-worker-comfy: Starting ComfyUI with optimization"
    python3 main.py --disable-auto-launch --disable-metadata --normalvram &
    COMFYUI_PID=$!
    echo "ComfyUI started in background (PID: $COMFYUI_PID)"

    # --- Wait for ComfyUI to be ready --- #
    HEALTH_CHECK_URL="http://127.0.0.1:8188/" 
    MAX_WAIT_SECONDS=120 # Maximum wait time (e.g., 2 minutes)
    WAIT_INTERVAL=2    # Check every 2 seconds
    SECONDS_WAITED=0

    echo "Waiting for ComfyUI to become ready at ${HEALTH_CHECK_URL}..."
    
    while true; do
        if [ $SECONDS_WAITED -ge $MAX_WAIT_SECONDS ]; then
            echo "Error: ComfyUI did not become ready within ${MAX_WAIT_SECONDS} seconds." >&2
            # Optional: kill the ComfyUI process if it failed to start properly
            # kill $COMFYUI_PID
            exit 1 # Exit if ComfyUI fails to start
        fi

        # Check if ComfyUI process is still running
        if ! ps -p $COMFYUI_PID > /dev/null; then
            echo "Error: ComfyUI process (PID: $COMFYUI_PID) terminated unexpectedly." >&2
            exit 1 # Exit if ComfyUI process died
        fi
        
        # Use curl to check the endpoint. -sS hides progress but shows errors. -f fails on HTTP errors.
        # We are checking for *any* successful HTTP response initially.
        # A short connect timeout prevents curl from hanging too long if the server isn't listening yet.
        response_code=$(curl --connect-timeout 1 --max-time 2 -o /dev/null -s -w "%{http_code}" ${HEALTH_CHECK_URL} || true)
        
        if [ "$response_code" -ge 200 ] && [ "$response_code" -lt 400 ]; then
            echo "ComfyUI is ready (HTTP status: $response_code)!"
            break # Exit loop when ready
        else
            # Log non-ready status codes for debugging, but don't treat them as fatal yet
            echo "ComfyUI not ready yet (Curl response code: $response_code). Waiting ${WAIT_INTERVAL}s..."
            sleep $WAIT_INTERVAL
            SECONDS_WAITED=$((SECONDS_WAITED + WAIT_INTERVAL))
        fi
    done
    # --- End Wait --- #

    echo "runpod-worker-comfy: Starting RunPod Handler"
    python3 -u /rp_handler.py
fi