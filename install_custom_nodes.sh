#!/usr/bin/env bash
set -euo pipefail

COMFYUI_PATH="${COMFYUI_PATH:-/workspace/ComfyUI}"
CN_DIR="${COMFYUI_PATH}/custom_nodes"

echo "[custom_nodes] target dir: ${CN_DIR}"
mkdir -p "${CN_DIR}"
cd "${CN_DIR}"

clone_or_update () {
  local repo_url="$1"
  local dir_name="$2"

  if [ -d "${dir_name}/.git" ]; then
    echo "[custom_nodes] updating ${dir_name}"
    git -C "${dir_name}" fetch --depth=1 origin main || git -C "${dir_name}" fetch --depth=1 || true
    git -C "${dir_name}" reset --hard FETCH_HEAD || true
  else
    echo "[custom_nodes] cloning ${repo_url} -> ${dir_name}"
    git clone --depth=1 "${repo_url}" "${dir_name}"
  fi
}

# 1) Manager (official)
clone_or_update "https://github.com/Comfy-Org/ComfyUI-Manager.git" "ComfyUI-Manager"

# 2) ControlNet Aux
clone_or_update "https://github.com/Fannovel16/comfyui_controlnet_aux.git" "comfyui_controlnet_aux"

# 3) IPAdapter+
clone_or_update "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git" "ComfyUI_IPAdapter_plus"

# 4) Impact Pack
clone_or_update "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" "ComfyUI-Impact-Pack"

# 5) Video Helper Suite
clone_or_update "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" "ComfyUI-VideoHelperSuite"

# 6) Frame Interpolation (RIFE alternative)
clone_or_update "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git" "ComfyUI-Frame-Interpolation"

# 7) Real-ESRGAN nodes (optional; ComfyUI also supports upscale models natively)
clone_or_update "https://github.com/zentrocdot/ComfyUI-RealESRGAN_Upscaler.git" "ComfyUI-RealESRGAN_Upscaler"

# 8) Qwen Edit Utils (maintained fork)
clone_or_update "https://github.com/lrzjason/Comfyui-QwenEditUtils.git" "Comfyui-QwenEditUtils"

echo "[custom_nodes] done"
