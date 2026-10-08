#!/usr/bin/env bash
# Builds an aarch64 stand-in libcuda.so.1 (every call returns CUDA_ERROR_NOT_SUPPORTED)
# so the cross-built ARM64 binary can load under qemu-aarch64 for startup / --help
# checks on a machine with no ARM GPU. See libcuda_stub.c.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=/usr/aarch64-linux-gnu/lib/libcuda.so.1
mkdir -p /usr/aarch64-linux-gnu/lib
CC=$(ls /usr/bin/aarch64-linux-gnu-gcc-14 /usr/bin/aarch64-linux-gnu-gcc 2>/dev/null | head -n1)
"$CC" -shared -fPIC -Wl,-soname,libcuda.so.1 -o "$OUT" "$HERE/libcuda_stub.c"
ln -sf libcuda.so.1 /usr/aarch64-linux-gnu/lib/libcuda.so
file "$OUT"
