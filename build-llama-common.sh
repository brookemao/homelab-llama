#!/usr/bin/env bash
# Shared local-only cmake tuning for the llama container builds.
# Build host == run host, so: static backends, host CPU only, native march.
# Both build-llama-rocm.sh and build-llama-vulkan.sh source this file.
# Override any of these in the environment if a portable/fat build is needed.
: "${GGML_BACKEND_DL:=OFF}"
: "${GGML_CPU_ALL_VARIANTS:=OFF}"
: "${GGML_NATIVE:=ON}"
