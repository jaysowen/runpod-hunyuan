echo "✨✨ ✨ ✨  ALL DONE - STARTING COMFYUI ✨ ✨ ✨ ✨ "

cd /workspace/ComfyUI
python main.py --listen --port 8188 --enable-cors-header --verbose $COMFYUI_EXTRA_ARGS &