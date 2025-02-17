# Use multi-stage build to optimize size
ARG CUDA_VERSION=12.4.0
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu22.04 as builder

# Install system dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /

# Copy scripts first to ensure they're available
COPY scripts/download_models.sh scripts/install_nodes.sh scripts/pre_start.sh scripts/start.sh /
RUN chmod +x /*.sh

# Clone ComfyUI and install base requirements
ARG COMFYUI_VERSION=latest
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    if [ "$COMFYUI_VERSION" != "latest" ]; then git checkout ${COMFYUI_VERSION}; fi && \
    pip install --no-cache-dir -r requirements.txt

# Copy workflow files directly to ComfyUI
COPY AllinOneUltra1.2.json AllinOneUltra1.3.json /ComfyUI/user/default/workflows/

# Pre-install common dependencies
ARG TORCH_VERSION=2.2.1
RUN pip install --no-cache-dir \
    opencv-python \
    numpy \
    torch==${TORCH_VERSION} \
    torchvision \
    pillow \
    transformers \
    scipy \
    requests \
    && pip cache purge

# Clone and install frequently used custom nodes during build
WORKDIR /ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth 1 https://github.com/WASasquatch/was-node-suite-comfyui.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    cd ComfyUI-Manager && pip install --no-cache-dir -r requirements.txt && \
    cd ../was-node-suite-comfyui && pip install --no-cache-dir -r requirements.txt && \
    cd ../ComfyUI-Impact-Pack && pip install --no-cache-dir -r requirements.txt && \
    pip cache purge

# Final stage
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu22.04

# Install runtime dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    openssh-server \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy ComfyUI from builder
COPY --from=builder /ComfyUI /ComfyUI

# Copy scripts
COPY --from=builder /*.sh /
RUN chmod +x /*.sh

# Create workspace directory
RUN mkdir -p /workspace

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PATH="/workspace/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive

# Expose ports
EXPOSE 8188 8888 22

CMD ["/start.sh"]