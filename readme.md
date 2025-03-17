# 🎮 ComfyUI WanVideo RunPod Template 1.0

Welcome to the most awesome ComfyUI setup you'll ever encounter! This template comes packed with everything you need to start creating amazing AI-generated videos and images using Wan Video models. 🚀

## UPDATE
17/03/25
- Added environment variables to control setup behavior:
  - `SKIP_DOWNLOADS=true`: Skip downloading models
  - `SKIP_NODES=true`: Skip installing custom nodes
  - Perfect for network drives & persistent storage


## ✨ Features

- 🎥 Pre-installed Wan 2.1 models for high-quality video generation
- 🧩 Carefully selected custom nodes for optimal workflow
- 🔧 Auto-installing workflow utilities
- 🎨 Built-in enhancement tools
- 🛠️ JupyterLab integration
- 🔍 Infinite Image Browser for managing output videos and images
- 🔒 SSH access support

## 🚀 Getting Started

### 1. Template Deployment

1. Head over to [RunPod.io](https://runpod.io?ref=0eayrc3z)
2. Click on `Deploy` and select `Template`
3. Search for `WanVideo - ComfyUI Manager - AllInOne1.0`
4. Choose your preferred GPU
5. Hit that `Deploy` button! 🎉

### 2. Environment Variables

When deploying, you can set these environment variables to control the startup behavior:

| Variable | Description | Default |
|----------|-------------|---------|
| `SKIP_DOWNLOADS` | Set to `true` to skip model downloads | `false` |
| `SKIP_NODES` | Set to `true` to skip node installations | `false` |
| `JUPYTERLAB_PASSWORD` | Set a password for JupyterLab | Empty (no password) |
| `PUBLIC_KEY` | Your SSH public key for secure access | Empty (SSH disabled) |

These are especially useful when:
- Using network drives or persistent storage
- Redeploying pods frequently
- You've already downloaded models and want faster startup


### 2. Accessing Your Instance

Once your pod is up and running, you'll see several URLs in your pod's overview:

- Will take around 20-25 mins to download all the models. Give it a few minutes after "⭐⭐⭐⭐⭐   ALL DONE - STARTING COMFYUI ⭐⭐⭐⭐⭐"

- 🎨 **ComfyUI**: `https://your-pod-id-8188.proxy.runpod.net`
- 📓 **JupyterLab**: `https://your-pod-id-8888.proxy.runpod.net`
- 🔍 **Image Browser**: `https://your-pod-id-8181.proxy.runpod.net`

### 3. Working with JupyterLab

- To set a password. on ENV template set JUPYTERLAB_PASSWORD = "password"
- Access JupyterLab using the URL from your pod's overview
- Default password is empty (just press Enter)
- All your work will be saved in the `/workspace` directory

### 4. Using the Image Browser

The template includes the Infinite Image Browser tool to help you manage ComfyUI output videos and images:

- Access the browser at `https://your-pod-id-8181.proxy.runpod.net`
- Or use the JupyterLab notebook at `/workspace/ComfyUI_Image_Browser.ipynb`
- Browse, search, and manage your ComfyUI output files
- Right-click on images/videos for additional options
- Search by filename, creation date, and metadata

### 5. SSH Access (Optional)

To enable SSH access:
1. Set your `PUBLIC_KEY` in the template settings
2. Connect using: `ssh -p <port> runpod@<ip-address>` Full link available on connect button on Runpod

## 📥 Downloading Models

This template includes a powerful and flexible system for downloading models using the `download-files.sh` script and a configuration file.

### Using the download-files.sh System

The template includes a convenient, configurable download system that makes it easy to manage model downloads:

1. **Edit the configuration file**:
   ```bash
   nano /workspace/files.txt
   ```

2. **Add model entries in this format**:
   ```
   type|folder|filename|url
   ```
   Where:
   - `type`: Use `normal` for direct downloads or `gdrive` for Google Drive files
   - `folder`: Destination subfolder (checkpoints, loras, embeddings, etc.)
   - `filename`: What to name the downloaded file
   - `url`: The download URL

   Example entries:
   ```
   normal|checkpoints|model1.safetensors|https://huggingface.co/org/model/resolve/main/model1.safetensors
   normal|loras|lora1.safetensors|https://civitai.com/api/download/models/12345
   gdrive|loras|lora_from_drive.safetensors|https://drive.google.com/uc?id=your_file_id
   ```

3. **Run the download script**:
   ```bash
   cd /workspace
   ./download-files.sh
   ```

4. **Monitor progress**:
   - The script shows download progress for each file
   - Each file is verified after download
   - A summary report is provided at the end

### Benefits of the files.txt System

- **Reproducible setup**: Document all your models in one place
- **Batch downloads**: Set up many downloads to run unattended
- **Cross-platform**: Works with Hugging Face, Civitai, Google Drive, and more
- **Automatic organization**: Files go to the correct folders automatically
- **Error handling**: Failed downloads are reported but don't stop the process
- **Verification**: Ensures all downloads completed successfully

### Direct Downloads (Alternative Method)

For one-off downloads, you can use wget directly:

1. Navigate to your desired directory:
```bash
cd /workspace/ComfyUI/models/checkpoints
```

2. Download using wget:
```bash
wget -O model_name.safetensors https://huggingface.co/model/resolve/main/model.safetensors
```

3. For large files with progress bar:
```bash
wget -q --show-progress https://huggingface.co/model/resolve/main/model.safetensors
```

4. For Civitai files with authentication:
```bash
wget -O model.safetensors "https://civitai.com/api/download/models/12345?type=Model&format=SafeTensor&token=your_token"
```

### Using files.txt

The template includes a file-based download system:

1. Edit `/workspace/files.txt` with your model information
2. Run the download script:
```bash
./download-files.sh
```

## 🎯 Pre-installed Models

### 🎬 Video Generation Models
- **Wan 2.1 Models**
  - `Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors` - Base model for video generation
  - `wan_2.1_vae.safetensors` - Dedicated VAE for Wan 2.1

### 🧠 Text Encoders
- `umt5_xxl_fp16.safetensors` - Advanced text encoder for Wan 2.1

### 👁️ CLIP Vision
- `clip_vision_h.safetensors` - Enhanced vision model for Wan Video

## 🧩 Custom Nodes Directory

This template includes a carefully selected set of nodes to provide optimal performance:

1. **Core Workflow Utilities**
   - `cg-use-everywhere` - Extended node usage
   - `ComfyUI-Custom-Scripts` - Workflow automation
   - `ComfyUI-Manager` - Node management and updates
   - `ComfyUI-Crystools` - Development utilities
   - `ComfyUI-KJNodes` - Specialized nodes

2. **UI Enhancement**
   - `rgthree-comfy` - Advanced workflow control
   - `was-node-suite-comfyui` - Comprehensive node collection

3. **Performance Optimization**
   - `ComfyUI-Impact-Pack` - Enhanced processing nodes

4. **User Experience**
   - `ComfyUI-Easy-Use` - Simplified interfaces

5. **Video Generation**
   - `ComfyUI-WanVideoWrapper` - Specialized nodes for Wan Video

## 💡 Tips for Best Results

1. **Start with sample workflows** found in the ComfyUI interface
2. **For high-quality videos**, use longer CFG values (7-9) and higher sampling steps (25+)
3. **Manage your VRAM** by using lower resolution for initial tests
4. **Use Text Prompts effectively** - detailed prompts work best with Wan Video models
5. **Browse and manage outputs** using the Infinite Image Browser

## 🔧 Troubleshooting

- If ComfyUI doesn't start, check the logs in JupyterLab terminal
- If models aren't loading, verify they downloaded correctly in `/ComfyUI/models/`
- For custom node issues, try restarting your pod or reinstalling via ComfyUI Manager

Need more help? Feel free to reach out or check the official documentation!