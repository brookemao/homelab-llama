#!/usr/bin/env bash
# Test the freshly built llama-local container with a Qwen3.8 thinking-mode preset.
# Models are read from /home/llama/models (host path, mounted at the same path).
# Sampling defaults follow https://unsloth.ai/docs/models/qwen3.8 (thinking mode).
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-localhost/llama-local:latest}"
MODELS_DIR="${MODELS_DIR:-/home/llama/models}"
PORT="${PORT:-8080}"
MODEL="${MODEL:-}"
REASONING_EFFORT="${REASONING_EFFORT:-xhigh}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--model FILE] [--models-dir DIR] [--port N] [--] [extra llama-server args...]

  --model FILE      GGUF basename or full path under MODELS_DIR.
                    If omitted, the first *.gguf under MODELS_DIR is used.
  --models-dir DIR  Host models directory (default: /home/llama/models).
  --port N          Host/container port (default: 8080).
  -h, --help        Show this help.

Env overrides: IMAGE_NAME, MODELS_DIR, PORT, MODEL, REASONING_EFFORT.
Any trailing args are appended to llama-server.
EOF
}

EXTRA_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --model)
      MODEL="${2:?--model needs a value}"
      shift 2
      ;;
    --model=*)
      MODEL="${1#--model=}"
      shift
      ;;
    --models-dir)
      MODELS_DIR="${2:?--models-dir needs a value}"
      shift 2
      ;;
    --models-dir=*)
      MODELS_DIR="${1#--models-dir=}"
      shift
      ;;
    --port)
      PORT="${2:?--port needs a value}"
      shift 2
      ;;
    --port=*)
      PORT="${1#--port=}"
      shift
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        EXTRA_ARGS+=("$1")
        shift
      done
      ;;
    *)
      # Bare first arg without a dash is treated as --model for convenience.
      if [ -z "${MODEL}" ] && [[ "$1" != -* ]]; then
        MODEL="$1"
        shift
      else
        EXTRA_ARGS+=("$1")
        shift
      fi
      ;;
  esac
done

if ! command -v podman >/dev/null 2>&1; then
  echo "error: podman not found in PATH" >&2
  exit 1
fi

if [ ! -d "${MODELS_DIR}" ]; then
  echo "error: models directory not found: ${MODELS_DIR}" >&2
  exit 1
fi

# Resolve the model to a host path under MODELS_DIR.
if [ -z "${MODEL}" ]; then
  MODEL="$(find "${MODELS_DIR}" -maxdepth 2 -type f -name '*.gguf' | sort | head -n 1 || true)"
  if [ -z "${MODEL}" ]; then
    echo "error: no *.gguf found under ${MODELS_DIR}; pass --model FILE" >&2
    exit 1
  fi
elif [[ "${MODEL}" != /* ]]; then
  MODEL="${MODELS_DIR}/${MODEL}"
fi

if [ ! -f "${MODEL}" ]; then
  echo "error: model file not found: ${MODEL}" >&2
  exit 1
fi

# Mounted at the same path, so host and container paths match.
MODEL_CONTAINER_PATH="${MODEL}"

echo "image:  ${IMAGE_NAME}"
echo "model:  ${MODEL_CONTAINER_PATH}"
echo "port:   ${PORT}"
echo "health: http://localhost:${PORT}/health"

# Sampling: Qwen3.8 thinking mode (temp 1.0, top_p 0.95, top_k 20, min_p 0.0,
# presence 0.0, repeat 1.0, xhigh reasoning by default).
# Note: -fa is an alias of --flash-attn, so it is passed once.
podman run --rm -it \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add video \
  --ipc=host \
  -p "${PORT}:8080" \
  -v "${MODELS_DIR}:${MODELS_DIR}:ro" \
  "${IMAGE_NAME}" \
  --model "${MODEL_CONTAINER_PATH}" \
  --host 0.0.0.0 \
  --port 8080 \
  --ctx-size 32768 \
  --batch-size 2048 \
  --ubatch-size 2048 \
  --threads 8 \
  --threads-batch 8 \
  --gpu-layers 999 \
  --split-mode none \
  --load-mode none \
  --parallel 4 \
  --flash-attn on \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --spec-type draft-mtp \
  --spec-draft-n-max 3 \
  --temp 1.0 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --presence-penalty 0.0 \
  --repeat-penalty 1.0 \
  --chat-template-kwargs "{\"reasoning_effort\":\"${REASONING_EFFORT}\"}" \
  "${EXTRA_ARGS[@]}"
