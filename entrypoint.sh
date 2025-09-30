#!/usr/bin/env bash
set -euo pipefail

# --- Base env (can be overridden via ENV) ---
export PYTHONUNBUFFERED=1
export HF_HOME="${HF_HOME:-/workspace/hf-cache}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-/workspace/hf-cache/transformers}"
export TORCH_HOME="${TORCH_HOME:-/workspace/torch-cache}"
export COMFYUI_PATH="${COMFYUI_PATH:-/workspace/ComfyUI}"
export COMFY_MODELS="${COMFY_MODELS:-/workspace/ComfyUI/models}"

# --- Optional download sync from Backblaze B2 on startup ---
# Required:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   B2_ENDPOINT
#   B2_SYNC_URL           (s3://bucket/path or s3://bucket)
# Optional:
#   B2_SYNC_SUBDIR
#   B2_SYNC_INCLUDE=*.safetensors,*.ckpt  (comma-separated)
#   B2_SYNC_EXCLUDE=*.tmp                 (comma-separated)
#   B2_CONCURRENCY (for s5cmd)
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
  if command -v s5cmd >/dev/null 2>&1; then
    local src="${B2_SYNC_URL%/}/"
    local dst="${dest%/}/"
    if s5cmd --endpoint-url "${B2_ENDPOINT}" --concurrency "${B2_CONCURRENCY:-64}" \
         sync ${include_flag} ${exclude_flag} "${src}*" "${dst}"; then
      echo "[startup] s5cmd download OK"
      return 0
    fi
    echo "[startup] s5cmd download failed, trying awscli"
  fi

  if command -v aws >/dev/null 2>&1; then
    local flags="--no-progress --only-show-errors --exact-timestamps"
    aws s3 sync "${B2_SYNC_URL}" "${dest}" --endpoint-url "${B2_ENDPOINT}" \
      ${flags} \
      ${B2_SYNC_INCLUDE:+--include "${B2_SYNC_INCLUDE}"} \
      ${B2_SYNC_EXCLUDE:+--exclude "${B2_SYNC_EXCLUDE}"} || true
  fi
}

# Run initial optional download
download_sync

# Start REST hook (port 8787). It will handle *manual* upload of changes.
# Security: set SYNC_TOKEN to require header X-Sync-Token
python /opt/sync_hook.py &
HOOK_PID=$!

# Start ComfyUI
cd "${COMFYUI_PATH}"
python main.py --port 8188 --listen 0.0.0.0 &
APP_PID=$!

# Graceful shutdown
terminate() {
  echo "[shutdown] stopping services..."
  kill -TERM "${HOOK_PID}" 2>/dev/null || true
  kill -TERM "${APP_PID}" 2>/dev/null || true
}
trap terminate SIGTERM SIGINT

wait ${APP_PID}
