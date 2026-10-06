#!/usr/bin/env bash
# Build llama-rocm container from llama.cpp submodule using podman.
# Uses .devops/rocm.Dockerfile with UBUNTU_VERSION=26.04 and ROCM_VERSION=10.0.0
# Local-only tuning from build-llama-common.sh:
# GGML_BACKEND_DL=OFF, GGML_CPU_ALL_VARIANTS=OFF, GGML_NATIVE=ON.
# The upstream Dockerfile is patched at build time so the submodule stays pristine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/build-llama-common.sh"
CONTEXT_DIR="${SCRIPT_DIR}/llama.cpp"
UPSTREAM_DOCKERFILE="${CONTEXT_DIR}/.devops/rocm.Dockerfile"

IMAGE_NAME="${IMAGE_NAME:-llama-rocm}"
UBUNTU_VERSION="26.04"
ROCM_VERSION="10.0.0"
# 26.04 images use the '-full' suffix (e.g. 10.0.0-full), not '-complete'.
BASE_ROCM_DEV_CONTAINER="docker.io/rocm/dev-ubuntu-${UBUNTU_VERSION}:${ROCM_VERSION}-full"
# Local GPU only: Radeon AI PRO R9700 (gfx1201). Fat build default trimmed for speed/size.
ROCM_DOCKER_ARCH="gfx1201"
# Dockerfile stages: full, light, server. Defaults to 'server' (last stage).
TARGET="${TARGET:-server}"

if ! command -v podman >/dev/null 2>&1; then
  echo "error: podman not found in PATH" >&2
  exit 1
fi

if [ ! -f "${UPSTREAM_DOCKERFILE}" ]; then
  echo "error: Dockerfile not found at ${UPSTREAM_DOCKERFILE}" >&2
  echo "hint: run 'git submodule update --init --recursive'" >&2
  exit 1
fi

# Patch the upstream Dockerfile into a temp file using the shared
# local-only flags from build-llama-common.sh:
# - static backends (no dlopen .so at runtime)
# - host CPU only (no fat CPU variants)
# - native march (build host == run host)
PATCHED_DOCKERFILE="$(mktemp)"
trap 'rm -f "${PATCHED_DOCKERFILE}"' EXIT

sed \
  -e "s/-DGGML_BACKEND_DL=ON/-DGGML_BACKEND_DL=${GGML_BACKEND_DL}/" \
  -e "s/-DGGML_CPU_ALL_VARIANTS=ON/-DGGML_CPU_ALL_VARIANTS=${GGML_CPU_ALL_VARIANTS}/" \
  "${UPSTREAM_DOCKERFILE}" > "${PATCHED_DOCKERFILE}"

if grep -q 'GGML_NATIVE' "${PATCHED_DOCKERFILE}"; then
  sed -i "s/-DGGML_NATIVE=OFF/-DGGML_NATIVE=${GGML_NATIVE}/" "${PATCHED_DOCKERFILE}"
else
  # Upstream rocm.Dockerfile currently sets no GGML_NATIVE flag (defaults OFF);
  # pin the build to the local CPU.
  sed -i "s/-DGGML_HIP=ON/-DGGML_HIP=ON -DGGML_NATIVE=${GGML_NATIVE}/" "${PATCHED_DOCKERFILE}"
fi

# Fail fast if the upstream cmake flags drift.
grep -q -- "-DGGML_BACKEND_DL=${GGML_BACKEND_DL}" "${PATCHED_DOCKERFILE}" || {
  echo "error: patched Dockerfile missing -DGGML_BACKEND_DL=${GGML_BACKEND_DL}" >&2
  exit 1
}
grep -q -- "-DGGML_CPU_ALL_VARIANTS=${GGML_CPU_ALL_VARIANTS}" "${PATCHED_DOCKERFILE}" || {
  echo "error: patched Dockerfile missing -DGGML_CPU_ALL_VARIANTS=${GGML_CPU_ALL_VARIANTS}" >&2
  exit 1
}
grep -q -- "-DGGML_NATIVE=${GGML_NATIVE}" "${PATCHED_DOCKERFILE}" || {
  echo "error: patched Dockerfile missing -DGGML_NATIVE=${GGML_NATIVE}" >&2
  exit 1
}

podman build \
  --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
  --build-arg "ROCM_VERSION=${ROCM_VERSION}" \
  --build-arg "BASE_ROCM_DEV_CONTAINER=${BASE_ROCM_DEV_CONTAINER}" \
  --build-arg "ROCM_DOCKER_ARCH=${ROCM_DOCKER_ARCH}" \
  --target "${TARGET}" \
  -t "${IMAGE_NAME}" \
  -f "${PATCHED_DOCKERFILE}" \
  "${CONTEXT_DIR}"
