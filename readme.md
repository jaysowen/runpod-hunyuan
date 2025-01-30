# ComfyUI HunyuanVideo Docker Container

This repository contains a Docker setup for running ComfyUI with HunyuanVideo and various custom nodes for AI video generation. The setup is optimized for use on Runpod.io and includes video processing capabilities.

## Features

- ComfyUI with HunyuanVideo support
- Custom nodes for video processing:
  - Video Helper Suite
  - Frame Interpolation
  - Noise Tools
  - Custom Scripts
  - Crystools
  - Impact Pack
  - RGThree's Nodes
  - KJNodes
- Built-in VS Code server
- Auto-recovery from crashes
- Pre-configured workflow for video generation
- Support for model management and custom LoRAs

## Prerequisites

- Runpod.io account
- Docker Hub account (if you want to build and push your own image)
- NVIDIA GPU with CUDA support
- PyTorch with CUDA 11.8 support

## Installation Notes

If you need to manually install or update PyTorch, use:

```bash
pip uninstall -y torch torchvision torchaudio
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```
## Quick Start on Runpod

1. Create a new pod on Runpod.io
2. Select a template with NVIDIA GPU support
3. Set the following environment variables:
   - `NVIDIA_VISIBLE_DEVICES=all`
   - `CUDA_VISIBLE_DEVICES=all`

## Ports

The container exposes two ports:
- `8188`: ComfyUI web interface
- `8080`: VS Code web interface

## Models

The following models are automatically downloaded on first run:

- `clip_l.safetensors`
- `llava_llama3_fp8_scaled.safetensors`
- `hunyuan_video_t2v_720p_bf16.safetensors`
- `hunyuan_video_vae_bf16.safetensors`
- `4x_foolhardy_Remacri.pth` (upscaler)

## Directory Structure

```
/workspace/
├── ComfyUI/
│   ├── models/
│   │   ├── diffusion_models/
│   │   ├── text_encoders/
│   │   ├── vae/
│   │   ├── upscale/
│   │   └── loras/
│   │       └── HUNYUAN/
│   │           └── custom/
│   ├── custom_nodes/
│   │   ├── ComfyUI-VideoHelperSuite/
│   │   ├── ComfyUI-Frame-Interpolation/
│   │   ├── ComfyUI_Noise/
│   │   ├── ComfyUI-Custom-Scripts/
│   │   ├── ComfyUI-Crystools/
│   │   ├── ComfyUI-Impact-Pack/
│   │   ├── rgthree-comfy/
│   │   └── ComfyUI-KJNodes/
│   ├── user/
│   │   └── default/
│   │       └── workflows/
│   │           └── workflow.json
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

## License

This project is open-source and available under the MIT License.
