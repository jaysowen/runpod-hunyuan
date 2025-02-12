# Hunyuan Video Generation on RunPod - Setup Guide

This guide will walk you through setting up and running the Hunyuan Video Generation environment on RunPod.

## Prerequisites

- A RunPod account (sign up at https://runpod.io)
- Basic familiarity with Docker and command-line interfaces

## Step 1: Setting Up Your RunPod Environment

1. Log in to your RunPod account
2. Navigate to the "Pods" section
3. Click "Deploy" to create a new pod

## Step 2: Selecting Template

1. In the template selection:
   - Select "Custom Template"
   - Container Image: `dihan/hunyuan-runpod:allinone`
   - Choose a GPU (Recommended: RTX 4090 or better)
   - Select at least 24GB RAM
   - Storage: Minimum 20GB (Recommended: 40GB)

## Step 3: Port Configuration

The following ports need to be exposed:
- `8188`: ComfyUI web interface
- `8080`: VS Code web interface

These are pre-configured in the template, but verify they're exposed in the RunPod UI.

## Step 4: Deploying Your Pod

1. Click "Deploy" to start your pod
2. Wait for the pod to initialize (this may take 5-10 minutes on first run due to model downloads)
3. Once the pod is running, you'll see "Connected" status

## Step 5: Accessing the Interfaces

After deployment, you can access:

1. ComfyUI Interface:
   - Click on "Connect" in your pod's details
   - Select port 8188
   - This opens the ComfyUI web interface

2. VS Code Interface:
   - Click on "Connect"
   - Select port 8080
   - This opens the VS Code web interface

## Step 6: Using the Environment

### ComfyUI Workflow

1. Navigate to the ComfyUI interface
2. Load the provided workflow:
   - Click the folder icon in the top-right
   - Select "AllinOneUltra1.3.json" from the workflows folder

### Model Files

The following models are automatically downloaded on first startup:
- `hunyuan_video_720_cfgdistill_bf16.safetensors` (UNET)
- `Long-ViT-L-14-GmP-SAE-TE-only.safetensors` (Text Encoder)
- `llava_llama3_fp8_scaled.safetensors` (Text Encoder)
- `hunyuan_video_vae_bf16.safetensors` (VAE)
- `clip-vit-large-patch14.safetensors` (CLIP Vision)
- `hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors` (FastVideo LoRA)

## Troubleshooting

### Common Issues

1. **Models Not Loading**
   - Check `/workspace/comfyui.log` for download errors
   - Verify disk space availability
   - Try running `/workspace/download-fix.sh` manually

2. **ComfyUI Not Starting**
   - Check `/workspace/comfyui.log` for errors
   - Ensure all required models are downloaded
   - Restart the pod if necessary

3. **VS Code Not Accessible**
   - Check `/workspace/vscode.log` for errors
   - Verify port 8080 is exposed and not blocked
   - Restart the pod if necessary

### Checking Logs

You can view logs through VS Code or terminal:
```bash
# ComfyUI logs
tail -f /workspace/comfyui.log

# VS Code logs
tail -f /workspace/vscode.log
```

## Maintenance

### Updating the Environment

To update to the latest version:
1. Stop your current pod
2. Delete the pod (your workspace volume will be preserved)
3. Deploy a new pod using the latest image

### Backup

Important files are stored in:
- `/workspace/ComfyUI/models/` - Model files
- `/workspace/ComfyUI/user/default/workflows/` - Workflows

## Support

For issues or questions:
1. Check the GitHub repository issues section
2. Join the ComfyUI Discord community
3. Check RunPod documentation for platform-specific issues

## Additional Resources

- [ComfyUI Documentation](https://github.com/comfyanonymous/ComfyUI)
- [RunPod Documentation](https://docs.runpod.io/)
- [Hunyuan Video Generation Repository](https://github.com/dihan/hunyuan-runpod)
