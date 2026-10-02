# homelab-llama
Scripts/setting for compiling and running llama.cpp on homelab

## Submodules

This repo includes [llama.cpp](https://github.com/ggml-org/llama.cpp) as a submodule at `llama.cpp/`.

Initialize the submodule and pull down the version specified in this repo:

```bash
git submodule update --init --recursive
```

Update the llama.cpp submodule version to the latest:

```bash
git submodule update --remote --merge
```

## Build

Build the `llama-local` container with podman (UBUNTU_VERSION=26.04, ROCM_VERSION=10.0.0):

```bash
./build-llama-local.sh
```

## Test

Run the freshly built `llama-local` image against models in `/home/llama/models`
(Qwen3.8 thinking-mode sampling + q8_0 KV cache, flash-attn, draft-mtp speculative decoding):

```bash
./test-llama-local.sh
./test-llama-local.sh --model Qwen3.8-27B-UD-Q4_K_XL.gguf
./test-llama-local.sh -- --verbose
```
