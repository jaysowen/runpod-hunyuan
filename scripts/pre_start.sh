#!/bin/bash

export PYTHONUNBUFFERED=1
export PATH="/workspace/venv/bin:$PATH"

echo "**** downloading models, please wait ****"
/download_models.sh

cd /workspace/ComfyUI
python main.py --listen --port 8188 --enable-cors-header --verbose $COMFYUI_EXTRA_ARGS &