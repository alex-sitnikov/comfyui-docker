#!/usr/bin/env bash
set -euo pipefail

COMFY_HOME="/workspace/ComfyUI"
CN_DIR="${COMFY_HOME}/custom_nodes"

mkdir -p "${CN_DIR}"
cd "${CN_DIR}"

# Node Manager
git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git ComfyUI-Manager

# ControlNet Auxiliary Preprocessors
git clone --depth=1 https://github.com/Fannovel16/comfyui_controlnet_aux.git comfyui_controlnet_aux

# IPAdapter Plus
git clone --depth=1 https://github.com/cubiq/ComfyUI_IPAdapter_plus.git ComfyUI_IPAdapter_plus

# Impact Pack
git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git ComfyUI-Impact-Pack

# Video Helper Suite
git clone --depth=1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ComfyUI-VideoHelperSuite

# RIFE interpolation
git clone --depth=1 https://github.com/KohakuBlueleaf/ComfyUI-RIFE.git ComfyUI-RIFE

# Real-ESRGAN nodes
git clone --depth=1 https://github.com/Acly/comfyui-inferlab-nodes.git comfyui-inferlab-nodes

# Qwen-Edit utils
git clone --depth=1 https://github.com/PowerBall253/Comfyui-QwenEditUtils.git Comfyui-QwenEditUtils

# WAN 2.5 API preview
git clone --depth=1 https://github.com/Comfy-Org/comfyui_api_nodes.git comfyui_api_nodes

# (optional) WAN 2.2 utils (MoE/DualSwitch)
# git clone --depth=1 https://github.com/Comfy-Org/WanComfyNodes.git WanComfyNodes

# Soft-install local requirements of nodes (avoid dependency nukes)
set +e
for d in "${CN_DIR}"/*; do
  if [ -f "${d}/requirements.txt" ]; then
    echo "[custom_nodes] installing requirements for $(basename "$d")"
    python -m pip install --no-deps -r "${d}/requirements.txt" || true
  fi
done
set -e

echo "[custom_nodes] done."
