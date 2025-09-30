# syntax=docker/dockerfile:1.7

# CUDA 12.6 runtime + cuDNN on Ubuntu 22.04
FROM nvidia/cuda:12.6.2-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/workspace/hf-cache \
    TRANSFORMERS_CACHE=/workspace/hf-cache/transformers \
    TORCH_HOME=/workspace/torch-cache \
    COMFYUI_PATH=/workspace/ComfyUI \
    COMFY_HOME=/workspace/ComfyUI \
    COMFY_MODELS=/workspace/ComfyUI/models

# 1) System packages (add build-essential for C/C++ builds)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    git git-lfs wget curl ca-certificates \
    software-properties-common gnupg \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 2) Python 3.11 + headers + pip bootstrap
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-venv python3.11-distutils python3.11-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py && \
    python3.11 /tmp/get-pip.py && rm -f /tmp/get-pip.py

# 3) venv on Python 3.11
RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# 4) Build tooling (+ Cython to satisfy native builds like insightface)
RUN python -m pip install --upgrade pip wheel setuptools cython==0.29.37

# 5) PyTorch/cuDNN (cu126) from official index (exact versions you requested)
RUN python -m pip install --index-url https://download.pytorch.org/whl/cu126 \
    torch==2.7.1+cu126 torchvision==0.22.1+cu126 torchaudio==2.7.1+cu126

# 6) Remaining pinned Python deps (except torch/xformers)
COPY requirements.txt /tmp/requirements.txt
RUN python -m pip install --no-deps -r /tmp/requirements.txt

# 7) Fast S3 sync tool (s5cmd) + awscli fallback for compatibility
RUN wget -q https://github.com/peak/s5cmd/releases/download/v2.3.0/s5cmd_2.3.0_Linux-64bit.tar.gz -O /tmp/s5cmd.tgz \
 && tar -xzf /tmp/s5cmd.tgz -C /tmp \
 && install -m 0755 /tmp/s5cmd /usr/local/bin/s5cmd \
 && rm -f /tmp/s5cmd.tgz
RUN python -m pip install --no-deps awscli

# 8) Git LFS and ComfyUI (nightly = main)
RUN git lfs install --system
RUN mkdir -p /workspace && \
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_PATH}

# 9) Custom nodes
ARG GITHUB_TOKEN=""
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
COPY install_custom_nodes.sh /opt/install_custom_nodes.sh
RUN bash /opt/install_custom_nodes.sh

# 10) Models/cache/output dirs
RUN mkdir -p \
    ${COMFY_MODELS}/checkpoints \
    ${COMFY_MODELS}/vae \
    ${COMFY_MODELS}/clip \
    ${COMFY_MODELS}/text_encoders \
    ${COMFY_MODELS}/diffusion_models \
    ${COMFY_MODELS}/insightface \
    ${COMFY_MODELS}/upscale_models \
    ${COMFY_MODELS}/RIFE \
    /workspace/hf-cache \
    /workspace/torch-cache \
    ${COMFY_HOME}/output \
    ${COMFY_HOME}/temp \
    ${COMFY_HOME}/custom_nodes

# 11) Non-root user and permissions
RUN useradd -ms /bin/bash comfy && chown -R comfy:comfy /workspace /opt

# 12) Healthcheck (ComfyUI on 8188)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -fsS http://127.0.0.1:8188 || exit 1

# 13) Expose and entrypoint
EXPOSE 8188 8787

COPY --chmod=0755 entrypoint.sh /opt/entrypoint.sh
COPY --chmod=0644 sync_hook.py  /opt/sync_hook.py
USER comfy

ENTRYPOINT ["/opt/entrypoint.sh"]