#!/usr/bin/env bash
# Build llama-local container from llama.cpp submodule using podman.
# Uses .devops/rocm.Dockerfile with UBUNTU_VERSION=26.04 and ROCM_VERSION=10.0.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="${SCRIPT_DIR}/llama.cpp"
DOCKERFILE="${CONTEXT_DIR}/.devops/rocm.Dockerfile"

IMAGE_NAME="llama-local"
UBUNTU_VERSION="26.04"
ROCM_VERSION="10.0.0"
# 26.04 images use the '-full' suffix (e.g. 10.0.0-full), not '-complete'.
BASE_ROCM_DEV_CONTAINER="docker.io/rocm/dev-ubuntu-${UBUNTU_VERSION}:${ROCM_VERSION}-full"
# Dockerfile stages: full, light, server. Defaults to 'server' (last stage).
TARGET="${TARGET:-server}"

if ! command -v podman >/dev/null 2>&1; then
  echo "error: podman not found in PATH" >&2
  exit 1
fi

if [ ! -f "${DOCKERFILE}" ]; then
  echo "error: Dockerfile not found at ${DOCKERFILE}" >&2
  echo "hint: run 'git submodule update --init --recursive'" >&2
  exit 1
fi

podman build \
  --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
  --build-arg "ROCM_VERSION=${ROCM_VERSION}" \
  --build-arg "BASE_ROCM_DEV_CONTAINER=${BASE_ROCM_DEV_CONTAINER}" \
  --target "${TARGET}" \
  -t "${IMAGE_NAME}" \
  -f "${DOCKERFILE}" \
  "${CONTEXT_DIR}"
