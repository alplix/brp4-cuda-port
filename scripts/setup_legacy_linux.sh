#!/usr/bin/env bash
set -euo pipefail
echo "===== CUDA 11.8 components (legacy/Kepler) ====="
mkdir -p /root/dl118 && cd /root/dl118
if [ ! -f red118.json ]; then curl -fsSL -o red118.json https://developer.download.nvidia.com/compute/cuda/redist/redistrib_11.8.0.json; fi
pick() { python3 -c "import json;d=json.load(open('/root/dl118/red118.json'));print(d['$1']['linux-x86_64']['relative_path'])"; }
BASE=https://developer.download.nvidia.com/compute/cuda/redist
rm -rf /opt/cuda118
mkdir -p /opt/cuda118
for comp in cuda_nvcc cuda_cudart libcufft; do
  rel=$(pick $comp)
  echo "== $rel"
  if [ ! -f "$(basename $rel)" ]; then curl -fsSLO "$BASE/$rel"; fi
  tar -xf "$(basename "$rel")" -C /opt/cuda118 --strip-components=1
done
ls /opt/cuda118/lib/libcufft_static.a /opt/cuda118/lib/libcufft_static_nocallback.a 2>&1 || true
/opt/cuda118/bin/nvcc --version | tail -1
echo "===== g++-11 for nvcc 11.8 header parsing ====="
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq gcc-11 g++-11 > /dev/null
/usr/bin/x86_64-linux-gnu-g++-11 --version | head -1
echo "LEGACY_SETUP_DONE"
