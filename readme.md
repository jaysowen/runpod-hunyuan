# 🎮 ComfyUI All-in-One RunPod Template 3.0

Welcome to the most awesome ComfyUI setup you'll ever encounter! This template comes packed with everything you need to start creating amazing AI-generated videos and images. 🚀

UPDATE
21/02/25
- Added download-files.sh - Add your models to files.txt and './download-files.sh' on terminal to download all your files from hugginface
- Updated Python to comfy recommened 3.12 - Uses Miniconda
  
20/02/25
- Everything working  well now udpated to the latest Pytorch and Cuda (Better performance)
- One anoying issue is the Easy Setnode refuse to work so I've created an alternative AllinoneUltra1.3 without that node 

## ✨ Features

- 🎥 Pre-installed HunyuanVideo models for video generation
- 🧩 Extensive collection of custom nodes
- 🔧 Auto-installing workflow utilities
- 🎨 Built-in enhancement tools
- 🛠️ JupyterLab integration (Removed VSCode)
- 🔒 SSH access support

## 🚀 Getting Started

### 1. Template Deployment

1. Head over to [RunPod.io]([https://runpod.io](https://runpod.io?ref=0eayrc3z))
2. Click on `Deploy` and select `Template`
3. Search for `Hunyuan Video - ComfyUI Manager - AllInOne3.0`
4. Choose your preferred GPU
5. Hit that `Deploy` button! 🎉

### 2. Accessing Your Instance

Once your pod is up and running, you'll see several URLs in your pod's overview:

- Will take around 25 mins to to download all the models (Will try to make this faster). Give it a few miniutes after "⭐⭐⭐⭐⭐   ALL DONE - STARTING COMFYUI ⭐⭐⭐⭐⭐"

- 🎨 **ComfyUI**: `https://your-pod-id-8188.proxy.runpod.net`
- 📓 **JupyterLab**: `https://your-pod-id-8888.proxy.runpod.net`

### 3. Working with JupyterLab

- To set a password. on ENV template set JUPYTERLAB_PASSWORD = "password"
- Access JupyterLab using the URL from your pod's overview
- Default password is empty (just press Enter)
- All your work will be saved in the `/workspace` directory

### 4. SSH Access (Optional)

To enable SSH access:
1. Set your `PUBLIC_KEY` in the template settings
2. Connect using: `ssh -p <port> runpod@<ip-address>` Full link avaliable on connet button on Runpod

## 📥 Downloading Models

### From HuggingFace 🤗 or ### From Civitai 🎨

1. Open JupyterLab terminal and navigate to your desired directory:
```bash
cd /workspace/ComfyUI/models/checkpoints
```

2. Download using wget (replace URL with your model link):
```bash
# For direct downloads
wget -O https://huggingface.co/CompVis/stable-diffusion-v1-4/resolve/main/sd-v1-4.ckpt

# For files requiring authentication
wget -O ArcaneJinx.safetensors "https://civitai.com/api/download/models/782002?type=Model&format=SafeTensor&token=xxxxxxxxxxxxxxxxxxxxxxxxxxx""
```

3. For large files, you can show progress:
```bash
wget -q --show-progress https://huggingface.co/model/resolve/main/model.safetensors
```



### Pro Tips 💡

1. **Organizing Downloads**:
```bash
# Create model type directories
mkdir -p /workspace/ComfyUI/models/{checkpoints,loras,controlnet,upscale_models}

# Download directly to specific folders
cd /workspace/ComfyUI/models/loras
```

2. **Batch Downloads**:
```bash
# Create a download list
cat << EOF > download_list.txt
URL1 filename1.safetensors
URL2 filename2.safetensors
EOF

# Download all files
while read url filename; do
    wget -q --show-progress -O "$filename" "$url"
done < download_list.txt
```

3. **Resume Interrupted Downloads**:
```bash
wget -c -q --show-progress "DOWNLOAD_URL"
```

----------


## 🎯 Pre-installed Models

### 🎬 Video Generation Models
- **HunyuanVideo Models**
  - `hunyuan_video_720_cfgdistill_bf16.safetensors` - Base model for video generation
  - `hunyuan_video_FastVideo_720_fp8_e4m3fn.safetensors` - Optimized FastVideo version
  - `hunyuan_video_vae_bf16.safetensors` - Dedicated VAE for video generation

### 🧠 Text Encoders
- **LLAVA & LongCLIP**
  - `Long-ViT-L-14-GmP-SAE-TE-only.safetensors` - Enhanced text understanding
  - `llava_llama3_fp8_scaled.safetensors` - Advanced language processing

### 👁️ CLIP Vision
- `model.safetensors` - OpenAI CLIP ViT-large-patch14 for visual understanding

## 🧩 Custom Nodes Directory

### 🎥 Video Processing Nodes
1. **ComfyUI-Frame-Interpolation**
   - Frame interpolation for smoother videos
   - Supports multiple interpolation methods

2. **ComfyUI-VideoHelperSuite**
   - Video frame extraction
   - Frame concatenation
   - Video assembly tools

3. **ComfyUI-HunyuanVideoMultiLora**
   - Multi-LoRA support for video generation
   - Style mixing capabilities

### 🎨 Image Enhancement
1. **ComfyUI-Detail-Daemon**
   - Detail enhancement
   - Texture refinement

2. **Image Motion Guider**
   - Motion consistency
   - Animation smoothing

3. **ComfyUI_Noise & CG-NoiseTools**
   - Advanced noise management
   - Grain and texture control

### 🛠️ Workflow Utilities
1. **Jovimetrix**
   - Advanced matrix operations
   - Mathematical transformations

2. **ComfyUI-Art-Venture**
   - Creative workflow tools
   - Style manipulation

3. **ComfyUI-Logic**
   - Conditional processing
   - Flow control nodes

4. **MX-Toolkit**
   - Utility functions
   - Workflow optimization

5. **Dream Project**
   - Advanced composition tools
   - Scene management

### 🔧 Core Utilities
1. **ComfyUI Manager**
   - Node management
   - Model downloading
   - Custom node installation

2. **WAS Node Suite**
   - Comprehensive node collection
   - Image processing tools
   - Advanced masks and filters

3. **Impact Pack**
   - Performance optimization
   - Advanced processing nodes

### 🎯 Special Purpose Nodes
1. **Comfy-Cliption**
   - CLIP text enhancement
   - Prompt optimization

2. **Dark Prompts**
   - Advanced prompt engineering
   - Negative prompt tools

3. **Denoise Chooser**
   - Custom denoising control
   - Quality management

4. **ComfyUI-GGUF**
   - GGUF model support
   - Optimized inference

5. **Comfy Image Saver**
   - Custom naming patterns
   - Automated organization

### ⚡ Additional Enhancement Nodes
1. **Ergouzi Nodes**
   - Chinese text support
   - Regional optimizations

2. **Various Nodes**
   - Miscellaneous utilities
   - Quality of life improvements

3. **JPS Nodes**
   - Specialized processing
   - Custom effects

4. **ComfyLiterals**
   - Direct value input
   - Parameter control

5. **TeaCache**
   - Memory management
   - Cache optimization

6. **Custom Scripts**
   - Workflow automation
   - Batch processing

7. **WaveSpeed**
   - Performance optimization
   - Processing acceleration

8. **Easy Use**
   - Simplified interfaces
   - Beginner-friendly tools

9. **Crystools**
   - Development utilities
   - Debug tools

10. **KJNodes**
    - Specialized video nodes
    - Animation tools

11. **RGThree Nodes**
    - Advanced workflow control
    - Custom interfaces

### 💡 Node Installation Tips
- All nodes are automatically installed during container startup
- Custom node settings are preserved in `/workspace/ComfyUI/custom_nodes`
- Node updates are handled automatically on container restart
- Additional nodes can be installed via ComfyUI Manager
