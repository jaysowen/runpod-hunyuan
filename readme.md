

# ComfyUI HunyuanVideo Docker Container

This repository contains a Docker setup for running ComfyUI with HunyuanVideo and various custom nodes for AI video generation. The setup is optimized for use on Runpod.io and includes video processing capabilities.

The build is based on the workflow by LatentDream's Hunyuan 💥 AllInOne ▪ Fast (+Tips)
https://civitai.com/models/1007385/hunyuan-allinone-fast-tips

## Features

- ComfyUI with HunyuanVideo support
- Extensive custom nodes collection for video processing and enhancement
- Built-in VS Code server
- Auto-recovery from crashes
- Pre-configured workflow for video generation
- Support for model management and custom LoRAs
- Automatic model verification and recovery

## Prerequisites

- Runpod.io account
- Docker Hub account (if you want to build and push your own image)
- NVIDIA GPU with CUDA support
- PyTorch with CUDA 11.8 support

## Model Verification

The container includes a model verification script that can be run manually to ensure all models are downloaded correctly:

```bash
chmod +x /workspace/verify_models.sh
./workspace/verify_models.sh
```

The script will:
- Check if all required models exist
- Verify each model file is at least 20MB in size
- Automatically redownload any corrupted or missing models
- Display final file sizes for verification

## Installation Notes

If you need to manually install or update PyTorch, use:

```bash
pip uninstall -y torch torchvision torchaudio
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

-----------------------------------------------------------------------------------------

## Quick Start on Runpod

1. Create a new pod on Runpod.io
2. Select a template with NVIDIA GPU support
3. Set the following environment variables:
   - `NVIDIA_VISIBLE_DEVICES=all`
   - `CUDA_VISIBLE_DEVICES=all`

## File Transfer on Runpod

You can transfer files to and from your pod using several methods:

1. **SFTP**: Use the built-in SFTP feature in RunPod's web interface
   - Navigate to your pod's "Connect" tab
   - Click "Connect" under "SFTP File Transfer"
   - Use provided credentials in your SFTP client

2. **Command Line**: Use `scp` or `rsync`
```bash
# Upload to pod
scp -P <port> local_file root@<pod_ip>:/workspace/

# Download from pod
scp -P <port> root@<pod_ip>:/workspace/file local_destination/
```

For more detailed instructions on file transfer, visit the [RunPod documentation](https://docs.runpod.io/pods/storage/transfer-files).

## Ports

The container exposes two ports:
- `8188`: ComfyUI web interface
- `8080`: VS Code web interface

## Models

The following models are automatically downloaded on first run:

### Hunyuan Models
- `hunyuan_video_t2v_720p_bf16.safetensors`
- `hunyuan_video_vae_bf16.safetensors`

### CLIP Models
- `clip_l.safetensors`
- `llava_llama3_fp8_scaled.safetensors`
- `Long-ViT-L-14-GmP-SAE-TE-only.safetensors`
- `clip-vit-large-patch14.safetensors`

### Upscalers
- `4x_foolhardy_Remacri.pth`

## Directory Structure

```
/workspace/
├── ComfyUI/
│   ├── models/
│   │   ├── unet/
│   │   ├── text_encoders/
│   │   ├── clip_vision/
│   │   ├── vae/
│   │   ├── upscale/
│   │   └── loras/
│   ├── custom_nodes/
│   │   ├── Core Nodes/
│   │   │   ├── ComfyUI-Manager/
│   │   │   ├── ComfyUI-VideoHelperSuite/
│   │   │   ├── ComfyUI-Frame-Interpolation/
│   │   │   ├── ComfyUI_Noise/
│   │   │   └── ComfyUI-Custom-Scripts/
│   │   ├── Utility Nodes/
│   │   │   ├── cg-noisetools/
│   │   │   ├── ComfyUI-Crystools/
│   │   │   ├── ComfyUI-Impact-Pack/
│   │   │   ├── rgthree-comfy/
│   │   │   └── ComfyUI-KJNodes/
│   │   ├── Enhancement Nodes/
│   │   │   ├── ComfyUI-Easy-Use/
│   │   │   ├── ComfyUI_essentials/
│   │   │   ├── cg-use-everywhere/
│   │   │   ├── ComfyUI-Detail-Daemon/
│   │   │   └── Comfyui_TTP_Toolset/
│   │   ├── Workflow Nodes/
│   │   │   ├── Jovimetrix/
│   │   │   ├── comfyui-art-venture/
│   │   │   ├── ComfyUI-Logic/
│   │   │   ├── ComfyUI-mxToolkit/
│   │   │   └── comfyui-dream-project/
│   │   └── Special Purpose/
│   │       ├── comfy-cliption/
│   │       ├── darkprompts/
│   │       ├── ComfyUI-DenoiseChooser/
│   │       ├── ComfyUI-GGUF/
│   │       ├── comfy-image-saver/
│   │       ├── ComfyUI-HunyuanVideoMultiLora/
│   │       ├── Comfyui-ergouzi-Nodes/
│   │       ├── comfyui-various/
│   │       ├── ComfyUI_JPS-Nodes/
│   │       ├── ComfyUI-ImageMotionGuider/
│   │       └── ComfyLiterals/
│   ├── user/
│   │   └── default/
│   │       └── workflows/
│   └── output/
└── logs/
```

## Building the Image

```bash
docker build -t your-dockerhub-username/comfyui-hunyuan:latest .
docker push your-dockerhub-username/comfyui-hunyuan:latest
```

## GitHub Actions

The repository includes a GitHub Actions workflow (`docker-publish.yml`) that automatically builds and pushes the Docker image to Docker Hub when changes are pushed to the main branch. To use this:

1. Add the following secrets to your GitHub repository:
   - `DOCKERHUB_USERNAME`
   - `DOCKERHUB_TOKEN`

2. Push to the main branch to trigger the build

## Usage

1. Access ComfyUI interface at `http://your-pod-ip:8188`
2. Access VS Code interface at `http://your-pod-ip:8080`
3. The included workflow (`workflow.json`) provides a starting point for video generation

## Included Workflow

The default workflow includes:
- Text-to-Video generation using HunyuanVideo
- Frame interpolation for smoother videos
- Upscaling capabilities using 4x_foolhardy_Remacri
- Video encoding with NVENC support

## Monitoring and Logs

Logs are stored in `/workspace/logs/`:
- `startup.log`: Container startup logs
- `comfyui.log`: ComfyUI application logs
- `vscode.log`: VS Code server logs

## Error Recovery

The container includes automatic error recovery:
- Monitors both ComfyUI and VS Code processes
- Automatically restarts crashed services
- Logs errors for debugging

## Environment Variables

- `NVIDIA_VISIBLE_DEVICES`: Control GPU visibility (default: all)
- `CUDA_VISIBLE_DEVICES`: Control CUDA device visibility (default: all)
- `PYTHONUNBUFFERED`: Control Python output buffering (default: 1)

## Troubleshooting

1. If models fail to download:
   ```bash
   # Check the logs
   cat /workspace/logs/startup.log
   ```

2. If services aren't starting:
   ```bash
   # Check process status
   ps aux | grep python
   ps aux | grep code-server
   ```

3. For CUDA issues:
   ```bash
   # Verify CUDA availability
   python3 -c "import torch; print(torch.cuda.is_available())"
   ```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request


# DEBUG DOWNLOAD FAIL
If for some reason the safetensor files didnt download. (You can check the size of the files on terminal with 'ls -l --block-size=M').

I've added a download-fix.sh file to the ./workspace folder which checks the size of models and download them if incorrect or 0mb which tends to happen.


# DEBUG FILES REQUIRED IF DONWLOAD FAILS

wget -O hunyuan_video_t2v_720p_bf16.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensor



wget -O llava_llama3_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors

wget -O llava_llama3_fp16.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp16.safetensors



wget -O clip_l.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/clip_l.safetensors

wget -O clip-vit-large-patch14.safetensors https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/model.safetensors

May not work with all models
wget -O hunyuan_video_vae_bf16_comfyorg https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/vae/hunyuan_video_vae_bf16.safetensors

Kijai version works on other models
wget -O hunyuan_video_vae_bf16.safetensors https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors

Optional
wget -O img2vid.safetensors https://huggingface.co/leapfusion-image2vid-test/image2vid-512x320/resolve/main/img2vid.safetensors

wget -O hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensors https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensor


ls -l --block-size=M

## License

This project is open-source and available under the MIT License.
