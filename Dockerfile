# Use multi-stage build to optimize size
ARG CUDA_VERSION=12.4.0
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu22.04 as builder

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3.10-venv \
    python3-pip \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3.10 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Set working directory
WORKDIR /build

# Copy scripts first to ensure they're available
COPY scripts/download_models.sh scripts/install_nodes.sh scripts/pre_start.sh scripts/start.sh /build/
RUN chmod +x /build/*.sh

# Clone ComfyUI and install base requirements
ARG COMFYUI_VERSION=latest
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    if [ "$COMFYUI_VERSION" != "latest" ]; then git checkout ${COMFYUI_VERSION}; fi && \
    pip install --no-cache-dir -r requirements.txt

# Pre-install common custom node dependencies
ARG TORCH_VERSION=2.2.1
RUN pip install --no-cache-dir \
    opencv-python \
    numpy \
    torch==${TORCH_VERSION} \
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
FROM nvidia/cuda:${CUDA_VERSION}.0-runtime-ubuntu22.04

# Copy Python virtual environment and ComfyUI from builder
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /build/ComfyUI /ComfyUI

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Copy scripts
COPY --from=builder /build/*.sh /
RUN chmod +x /*.sh

# Create required directories
RUN mkdir -p /workspace && \
    mkdir -p /ComfyUI/models/{unet,text_encoders,clip_vision,vae}

EXPOSE 8188 8888 22

ENV PYTHONUNBUFFERED=1
ENV PATH="/opt/venv/bin:/workspace/bin:$PATH"
ENV VIRTUAL_ENV=/opt/venv

CMD ["/start.sh"]