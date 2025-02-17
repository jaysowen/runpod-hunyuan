# Use multi-stage build to optimize size
ARG PYTHON_VERSION
ARG CUDA_VERSION
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04 as builder

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python${PYTHON_VERSION} \
    python3-pip \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Clone ComfyUI and install base requirements
ARG COMFYUI_VERSION
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    git checkout ${COMFYUI_VERSION} && \
    pip install --no-cache-dir -r requirements.txt

# Pre-install common custom node dependencies
RUN pip install --no-cache-dir \
    opencv-python \
    numpy \
    torch \
    torchvision \
    pillow \
    transformers \
    scipy \
    requests

# Clone and install frequently used custom nodes during build
WORKDIR /build/ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    cd ComfyUI-Manager && pip install --no-cache-dir -r requirements.txt && \
    cd ../was-node-suite-comfyui && pip install --no-cache-dir -r requirements.txt && \
    cd ../ComfyUI-Impact-Pack && pip install --no-cache-dir -r requirements.txt

# Final stage
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Copy Python environment and ComfyUI from builder
COPY --from=builder /usr/local/lib/python3.8 /usr/local/lib/python3.8
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /build/ComfyUI /ComfyUI

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    python${PYTHON_VERSION} \
    python3-pip \
    git \
    wget \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Copy scripts
COPY download_models.sh install_nodes.sh pre_start.sh start.sh /
RUN chmod +x /*.sh

# Create required directories
# RUN mkdir -p /workspace && \
#     mkdir -p /ComfyUI/models/{unet,text_encoder,clip_vision,vae}

EXPOSE 8188 8888 22

ENV PYTHONUNBUFFERED=1
ENV PATH="/workspace/bin:$PATH"

CMD ["/start.sh"]