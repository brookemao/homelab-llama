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

Build the `llama-rocm` container with podman (UBUNTU_VERSION=26.04, ROCM_VERSION=10.0.0,
`gfx1201` only):

```bash
./build-llama-rocm.sh
```

Build the `llama-vulkan` container with podman:

```bash
./build-llama-vulkan.sh
```

Both builds patch their upstream Dockerfile (`.devops/rocm.Dockerfile` /
`.devops/vulkan.Dockerfile`) at build time so the submodule stays pristine,
forcing local-only tuning shared via `build-llama-common.sh`:

- `GGML_BACKEND_DL=OFF` (static backends, no dlopen `.so` at runtime)
- `GGML_CPU_ALL_VARIANTS=OFF` (no fat CPU binaries)
- `GGML_NATIVE=ON` (tuned to the build host CPU; build host == run host)

Images are therefore not portable to other CPUs.
