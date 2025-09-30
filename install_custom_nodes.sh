#!/usr/bin/env bash
set -euo pipefail

COMFY_HOME="/workspace/ComfyUI"
CN_DIR="${COMFY_HOME}/custom_nodes"
mkdir -p "${CN_DIR}"
cd "${CN_DIR}"

# Build base URL: authenticated if GITHUB_TOKEN is present
BASE_URL="https://github.com"
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  BASE_URL="https://${GITHUB_TOKEN}@github.com"
fi

retry_clone () {
  local url="$1"
  local dir="$2"
  local tries=5
  local delay=2
  local i=1
  while true; do
    echo "[custom_nodes] cloning ${url} -> ${dir} (attempt ${i}/${tries})"
    if git clone --depth=1 "${url}" "${dir}"; then
      echo "[custom_nodes] OK: ${dir}"
      return 0
    fi
    if [[ $i -ge $tries ]]; then
      echo "[custom_nodes] ERROR: failed to clone ${url} after ${tries} attempts"
      return 1
    fi
    sleep "${delay}"
    delay=$(( delay * 2 ))
    i=$(( i + 1 ))
  done
}

# Node Manager
retry_clone "${BASE_URL}/ltdrdata/ComfyUI-Manager.git" "ComfyUI-Manager"

# ControlNet Auxiliary Preprocessors
retry_clone "${BASE_URL}/Fannovel16/comfyui_controlnet_aux.git" "comfyui_controlnet_aux"

# IPAdapter Plus
retry_clone "${BASE_URL}/cubiq/ComfyUI_IPAdapter_plus.git" "ComfyUI_IPAdapter_plus"

# Impact Pack
retry_clone "${BASE_URL}/ltdrdata/ComfyUI-Impact-Pack.git" "ComfyUI-Impact-Pack"

# Video Helper Suite
retry_clone "${BASE_URL}/Kosinkadink/ComfyUI-VideoHelperSuite.git" "ComfyUI-VideoHelperSuite"

# ComfyUI VFI (Frame Interpolation)
retry_clone "${BASE_URL}/Fannovel16/ComfyUI-Frame-Interpolation.git" "ComfyUI-Frame-Interpolation"

# Real-ESRGAN nodes
retry_clone "${BASE_URL}/Acly/comfyui-inferlab-nodes.git" "comfyui-inferlab-nodes"

# Qwen-Edit utils
retry_clone "${BASE_URL}/PowerBall253/Comfyui-QwenEditUtils.git" "Comfyui-QwenEditUtils"

# WAN 2.5 API preview
retry_clone "${BASE_URL}/Comfy-Org/comfyui_api_nodes.git" "comfyui_api_nodes"

# WAN 2.2 utils (MoE/DualSwitch)
retry_clone "${BASE_URL}/Comfy-Org/WanComfyNodes.git" "WanComfyNodes"

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
