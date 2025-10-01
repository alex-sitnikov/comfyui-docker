#!/usr/bin/env bash
set -euo pipefail

# --- Base env (can be overridden via ENV) ---
export PYTHONUNBUFFERED=1
export HF_HOME="${HF_HOME:-/workspace/hf-cache}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-/workspace/hf-cache/transformers}"
export TORCH_HOME="${TORCH_HOME:-/workspace/torch-cache}"
export COMFYUI_PATH="${COMFYUI_PATH:-/workspace/ComfyUI}"
export COMFY_MODELS="${COMFY_MODELS:-/workspace/ComfyUI/models}"

ensure_layout() {
  mkdir -p \
    "${COMFY_MODELS}/checkpoints" \
    "${COMFY_MODELS}/vae" \
    "${COMFY_MODELS}/clip" \
    "${COMFY_MODELS}/text_encoders" \
    "${COMFY_MODELS}/diffusion_models" \
    "${COMFY_MODELS}/insightface" \
    "${COMFY_MODELS}/upscale_models" \
    "${COMFY_MODELS}/RIFE" \
    "${HF_HOME}" \
    "${TORCH_HOME}" \
    "${COMFYUI_PATH}/output" \
    "${COMFYUI_PATH}/temp" \
    "${COMFYUI_PATH}/custom_nodes"
}

# If /workspace is an empty fresh volume, ComfyUI baked into the image got shadowed by the mount.
# Clone ComfyUI (+ custom nodes) into the volume on first run.
bootstrap_comfyui_if_missing() {
  if [[ ! -f "${COMFYUI_PATH}/main.py" ]]; then
    echo "[bootstrap] ComfyUI not found in ${COMFYUI_PATH} → cloning fresh copy"
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_PATH}"
    # Install custom nodes into the mounted volume
    if [[ -x "/opt/install_custom_nodes.sh" ]]; then
      COMFYUI_PATH="${COMFYUI_PATH}" bash /opt/install_custom_nodes.sh || true
    fi
  fi
}

# --- Optional download sync from Backblaze B2 on startup ---
# Required:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   B2_ENDPOINT
#   B2_SYNC_URL           (s3://bucket/path or s3://bucket)
# Optional:
#   B2_SYNC_SUBDIR
#   B2_SYNC_INCLUDE=*.safetensors,*.ckpt  (comma-separated)
#   B2_SYNC_EXCLUDE=*.tmp                 (comma-separated)
download_sync() {
  if [[ -z "${B2_SYNC_URL:-}" || -z "${B2_ENDPOINT:-}" || -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    echo "[startup] download sync disabled"
    return 0
  fi
  local dest="${COMFY_MODELS}"
  if [[ -n "${B2_SYNC_SUBDIR:-}" ]]; then
    dest="${COMFY_MODELS}/${B2_SYNC_SUBDIR}"
  fi
  mkdir -p "${dest}"

  local include_flag="" exclude_flag=""
  if [[ -n "${B2_SYNC_INCLUDE:-}" ]]; then
    IFS=',' read -ra incs <<< "${B2_SYNC_INCLUDE}"
    for p in "${incs[@]}"; do include_flag+=" --include ${p}"; done
  fi
  if [[ -n "${B2_SYNC_EXCLUDE:-}" ]]; then
    IFS=',' read -ra excs <<< "${B2_SYNC_EXCLUDE}"
    for p in "${excs[@]}"; do exclude_flag+=" --exclude ${p}"; done
  fi

  echo "[startup] downloading models from ${B2_SYNC_URL} → ${dest}"

  # Prefer s5cmd (without --concurrency: some builds don't support it)
  if command -v s5cmd >/dev/null 2>&1; then
    local src="${B2_SYNC_URL%/}/"
    local dst="${dest%/}/"
    if s5cmd --endpoint-url "${B2_ENDPOINT}" sync ${include_flag} ${exclude_flag} "${src}*" "${dst}"; then
      echo "[startup] s5cmd download OK"
      return 0
    fi
    echo "[startup] s5cmd download failed, trying awscli"
  fi

  # Fallback: awscli (now installed with deps, so botocore is present)
  if command -v aws >/dev/null 2>&1; then
    local flags="--no-progress --only-show-errors --exact-timestamps"
    aws s3 sync "${B2_SYNC_URL}" "${dest}" --endpoint-url "${B2_ENDPOINT}" \
      ${flags} \
      ${B2_SYNC_INCLUDE:+--include "${B2_SYNC_INCLUDE}"} \
      ${B2_SYNC_EXCLUDE:+--exclude "${B2_SYNC_EXCLUDE}"} || true
  else
    echo "[startup] awscli not found; skipping fallback"
  fi
}

ensure_layout
bootstrap_comfyui_if_missing
download_sync

# Start REST hook (port 8787). It will handle *manual* upload of changes.
# Security: set SYNC_TOKEN to require header X-Sync-Token
python /opt/sync_hook.py &

# Launch ComfyUI
cd "${COMFYUI_PATH}"
exec python main.py --port 8188 --listen 0.0.0.0