# Start with RunPod CUDA base image
FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    git \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install code-server (VS Code)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Create and activate virtual environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Clone ComfyUI
WORKDIR /workspace
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# Install Python dependencies
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
RUN pip install -r requirements.txt
RUN pip install moviepy opencv-python pillow

# Copy setup script
COPY setup.sh /workspace/setup.sh
RUN chmod +x /workspace/setup.sh
RUN /workspace/setup.sh

# Copy startup script
COPY start.sh /workspace/start.sh
RUN chmod +x /workspace/start.sh

# Expose ports
EXPOSE 8080 8188

# Set working directory
WORKDIR /workspace

CMD ["/workspace/start.sh"]