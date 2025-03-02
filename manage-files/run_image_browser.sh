#!/bin/bash
# File: /workspace/run_image_browser.sh

cd /workspace/sd-webui-infinite-image-browsing
python app.py --port=8181 --extra_paths /workspace/ComfyUI/output --host=0.0.0.0