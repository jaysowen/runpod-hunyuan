# Use RunPod pytorch base image which includes JupyterLab
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set environment variables
ENV SHELL=/bin/bash
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /

# System setup and dependencies
RUN apt-get update --yes && \
    apt-get upgrade --yes && \
    apt install --yes --no-install-recommends \
    git \
    wget \
    curl \
    bash \
    libgl1 \
    software-properties-common \
    openssh-server \
    ffmpeg \
    nodejs \
    npm && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

RUN ln -s /usr/bin/python3.11 /usr/bin/python && \
    rm /usr/bin/python3 && \
    ln -s /usr/bin/python3.11 /usr/bin/python3 && \
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python get-pip.py

# Install Python packages
RUN pip install --upgrade --no-cache-dir pip && \
    pip install --upgrade setuptools && \
    pip install --upgrade wheel && \
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# Install Python packages
RUN pip install --upgrade --no-cache-dir pip && \
    pip install --upgrade setuptools wheel && \
    pip install numpy && \
    pip install --no-cache-dir triton sageattention \
    pip install --upgrade setuptools && \
    pip install --upgrade wheel

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

RUN mkdir -p /workspace

# Create workspace directory
WORKDIR /workspace
# Clone and set up ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git


COPY download-fix.sh /download-fix.sh
COPY AllinOneUltra1.2.json workspace/ComfyUI/user/default/workflows/AllinOneUltra1.2.json
COPY AllinOneUltra1.3.json /workspace/ComfyUI/user/default/workflows/AllinOneUltra1.3.json

WORKDIR /workspace/ComfyUI
# Install ComfyUI requirements
RUN pip install -r requirements.txt
RUN pip install moviepy opencv-python pillow


WORKDIR /workspace/ComfyUI

# Install custom nodes
RUN mkdir -p custom_nodes && \
    cd custom_nodes && \
# Create workspace directory
WORKDIR /workspace

# Clone and set up ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# Install ComfyUI requirements
RUN pip install -r requirements.txt
RUN pip install moviepy opencv-python pillow

# Install custom nodes including ComfyUI-Manager and additional requested nodes
# Install custom nodes
RUN mkdir -p custom_nodes && \
    cd custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/chengzeyi/Comfy-WaveSpeed.git && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui
    

# Install custom nodes requirements
RUN cd custom_nodes/ComfyUI-Manager && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Easy-Use && pip install -r requirements.txt || true  && \
    cd ../ComfyUI-Crystools && pip install -r requirements.txt || true && \
    cd ../ComfyUI-KJNodes && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Impact-Pack && pip install -r requirements.txt || true && \
    cd ../ComfyUI-Custom-Scripts && pip install -r requirements.txt || true && \
    cd ../rgthree-comfy && pip install -r requirements.txt || true && \
    cd ../Comfy-WaveSpeed && pip install -r requirements.txt || true && \
    cd ../was-node-suite-comfyui && pip install -r requirements.txt || true



RUN mkdir -p models/upscale && \
    cd models/upscale && \
    wget -O 4x_foolhardy_Remacri.pth https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth


# Create model directories and download models
# RUN mkdir -p models/{unet,text_encoders,vae,upscale,loras} && \
#     cd models && \
#     cd unet && \
#     wget -O hunyuan_video_720_cfgdistill_bf16.safetensors https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_720_cfgdistill_bf16.safetensors && \
#     cd ../vae && \
#     wget -O img2vid.safetensors https://huggingface.co/leapfusion-image2vid-test/image2vid-512x320/resolve/main/img2vid.safetensors && \
#     wget -O hunyuan_video_vae_bf16.safetensors https://huggingface.co/Kijai/HunyuanVideo_comfy/resolve/main/hunyuan_video_vae_bf16.safetensors && \
#     cd ../upscale && \
#     wget -O 4x_foolhardy_Remacri.pth https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth && \
#     cd ../text_encoders && \
#     wget -O clip_l.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/clip_l.safetensors && \
#     wget -O llava_llama3_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/HunyuanVideo_repackaged/resolve/main/split_files/text_encoders/llava_llama3_fp8_scaled.safetensors


# Rest of the Dockerfile remains the same...
COPY <<-'EOT' /pre_start.sh
#!/bin/bash
cd /workspace
if [ -d "ComfyUI" ]; then
    /install-repositories.sh
fi

# Start ComfyUI in the background
cd /workspace/ComfyUI
nohup python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /workspace/comfyui.log 2>&1 &

# Start VS Code in the background with no auth
nohup code-server --bind-addr 0.0.0.0:8080 --auth none > /workspace/vscode.log 2>&1 &
EOT

RUN chmod +x /pre_start.sh

# Expose ports for VS Code Web and ComfyUI
EXPOSE 8080 8188 8888

# Use RunPod's default start script
CMD ["/start.sh"]