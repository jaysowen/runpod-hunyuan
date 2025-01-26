# Dockerfile
FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

WORKDIR /

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Configure code-server
RUN mkdir -p ~/.config/code-server
RUN echo "bind-addr: 0.0.0.0:8080\nauth: password\npassword: comfyui\ncert: false" > ~/.config/code-server/config.yaml

# Clone ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /ComfyUI

# Install Python dependencies
RUN pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
RUN pip3 install -r requirements.txt
RUN pip3 install runpod

# Create model directories
RUN mkdir -p models/diffusion_models
RUN mkdir -p models/text_encoders
RUN mkdir -p models/vae

# Download model files
RUN wget -O models/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/diffusion_models/hunyuan_video_t2v_720p_bf16.safetensors?download=true
RUN wget -O models/text_encoders/clip_l.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/clip_l.safetensors?download=true
RUN wget -O models/text_encoders/llava_llama3_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors?download=true
RUN wget -O models/vae/hunyuan_video_vae_bf16.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/vae/hunyuan_video_vae_bf16.safetensors?download=true

# Copy handler code
COPY handler.py /ComfyUI/
COPY workflow.json /ComfyUI/

# Add startup script
COPY --chmod=755 <<EOF /start.sh
#!/bin/bash
code-server --bind-addr 0.0.0.0:8080 & 
python3 -u handler.py
EOF

# Expose port for code-server
EXPOSE 8080

# Start both services
CMD ["/start.sh"]