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

# Create workspace directory
WORKDIR /workspace

# Clone ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# Install Python dependencies
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
RUN pip install -r requirements.txt
RUN pip install moviepy opencv-python pillow

# Copy our scripts
COPY setup.sh /workspace/setup.sh
COPY start.sh /workspace/start.sh

# Make scripts executable
RUN chmod +x /workspace/setup.sh /workspace/start.sh

# Run setup
RUN /workspace/setup.sh

# Expose ports
EXPOSE 8080 8188

# Set working directory
WORKDIR /workspace

# Set the entrypoint to our start script
ENTRYPOINT ["/workspace/start.sh"]