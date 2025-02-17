echo "✨✨ ✨ ✨  ALL DONE - STARTING COMFYUI ✨ ✨ ✨ ✨ "

# Only start ComfyUI and download models if not in install_only mode
if [ "$1" != "install_only" ]; then
    cd /workspace/ComfyUI
    python main.py --listen --port 8188 --enable-cors-header --verbose $COMFYUI_EXTRA_ARGS &
fi