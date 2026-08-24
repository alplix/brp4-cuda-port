#!/usr/bin/env bash
set -e
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  crossbuild-essential-arm64 gcc-14-aarch64-linux-gnu g++-14-aarch64-linux-gnu \
  libgsl-dev:arm64 libxml2-dev:arm64 zlib1g-dev:arm64 liblzma-dev:arm64 \
  libzstd-dev:arm64 libssl-dev:arm64 libfftw3-dev:arm64 \
  >/dev/null
echo "--- cross compilers:"
ls /usr/bin/aarch64-linux-gnu-g++* /usr/bin/aarch64-linux-gnu-gcc* 2>/dev/null | head -6
echo "--- sample libs:"
ls /usr/lib/aarch64-linux-gnu/libgsl.a /usr/lib/aarch64-linux-gnu/libfftw3f.a /usr/lib/aarch64-linux-gnu/libbfd.a /usr/lib/aarch64-linux-gnu/libiberty.a /usr/lib/aarch64-linux-gnu/libzstd.a 2>&1 | tail -6

# ---- CUDA 12.9 aarch64 redist (nvcc/cudart/libcufft) ----
mkdir -p /opt/cuda129-arm64/dl && cd /opt/cuda129-arm64/dl
JSON=https://developer.download.nvidia.com/compute/cuda/redist/redistrib_12.9.1.json
for comp in cuda_nvcc cuda_cudart libcufft; do
  # extract linux-aarch64 relative path + version from json via python
  read -r REL < <(curl -fsSL $JSON | python3 -c "
import json,sys
d=json.load(sys.stdin)[sys.argv[1]]['linux-aarch64']
print(d['relative_path'])" $comp)
  F=$(basename $REL)
  if [ ! -s "$F" ]; then curl -fsSL "https://developer.download.nvidia.com/compute/cuda/redist/$REL" -o "$F"; fi
  tar xf "$F" -C /opt/cuda129-arm64
done
mv /opt/cuda129-arm64/cuda_nvcc-linux-aarch64-* /tmp_mvnvcc 2>/dev/null || true
# merge layout like x86_64: everything under one root
mkdir -p /opt/cuda129-arm64/root
for d in /opt/cuda129-arm64/cuda_*; do cp -a "$d"/. /opt/cuda129-arm64/root/; done
ls /opt/cuda129-arm64/root/bin/nvcc /opt/cuda129-arm64/root/lib/libcufft_static_nocallback.a /opt/cuda129-arm64/root/lib/stubs/libcuda.so 2>&1 | tail -4
echo "--- nvcc arch check:"
file /opt/cuda129-arm64/root/bin/nvcc | cut -d, -f1-2
