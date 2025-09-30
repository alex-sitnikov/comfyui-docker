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

# 1) System packages (minimal set required by ComfyUI/custom nodes)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    git wget curl ca-certificates \
    software-properties-common gnupg \
    && rm -rf /var/lib/apt/lists/*

# 2) Python 3.11 + pip bootstrap
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-venv python3.11-distutils && \
    rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py && \
    python3.11 /tmp/get-pip.py && rm -f /tmp/get-pip.py

# 3) Dedicated venv on Python 3.11
RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# 4) Build tooling
RUN python -m pip install --upgrade pip wheel setuptools

# 5) PyTorch/cuDNN (cu126) from official index (exact versions you requested)
RUN python -m pip install --index-url https://download.pytorch.org/whl/cu126 \
    torch==2.7.1+cu126 torchvision==0.22.1+cu126 torchaudio==2.7.1+cu126

# 6) Remaining pinned Python deps (except torch/xformers)
COPY requirements.txt /tmp/requirements.txt
RUN python -m pip install --no-deps -r /tmp/requirements.txt

# 7) xFormers wheel compatible with Torch 2.7.1 + cu126
RUN python -m pip install --index-url https://download.pytorch.org/whl/xformers/ xformers

# 8) Fast S3 sync tool (s5cmd) + awscli fallback for compatibility
RUN wget -q https://github.com/peak/s5cmd/releases/download/v2.3.0/s5cmd_2.3.0_Linux-64bit.tar.gz -O /tmp/s5cmd.tgz \
 && tar -xzf /tmp/s5cmd.tgz -C /tmp \
 && install -m 0755 /tmp/s5cmd /usr/local/bin/s5cmd \
 && rm -f /tmp/s5cmd.tgz
RUN python -m pip install --no-deps awscli

# 9) Git LFS and ComfyUI (nightly = main)
RUN git lfs install
RUN mkdir -p /workspace && \
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_PATH}

# 10) Custom nodes
COPY install_custom_nodes.sh /opt/install_custom_nodes.sh
RUN bash /opt/install_custom_nodes.sh

# 11) Models/cache/output dirs
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

# 12) Non-root user
RUN useradd -ms /bin/bash comfy && chown -R comfy:comfy /workspace /opt
USER comfy

# 13) Healthcheck (ComfyUI on 8188)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=10 \
  CMD curl -fsS http://127.0.0.1:8188 || exit 1

# 14) Entrypoint + REST hook (port 8787)
EXPOSE 8188
EXPOSE 8787
COPY entrypoint.sh /opt/entrypoint.sh
COPY sync_hook.py /opt/sync_hook.py
RUN chmod +x /opt/entrypoint.sh /opt/install_custom_nodes.sh
ENTRYPOINT ["/opt/entrypoint.sh"]
