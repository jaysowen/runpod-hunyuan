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
