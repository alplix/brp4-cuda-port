#!/usr/bin/env bash
set -euo pipefail

echo "===== [1] BOINC libraries ====="
cd /root/build/3rdparty/boinc-current_brp_apps/lib
sed -i 's|^CC = .*|CC = g++ -I ../ -std=gnu++11 -Wno-deprecated-declarations|' Makefile.linux
sed -i 's|rsa = EVP_PKEY_get0_RSA(pubKey);|rsa = const_cast<RSA *>(EVP_PKEY_get0_RSA(pubKey));|' crypt.cpp
make -f Makefile.linux -j8 > /root/boinc_build.log 2>&1 || { tail -20 /root/boinc_build.log; exit 1; }
g++ -I../ -I. -I../api -std=gnu++11 -Wno-deprecated-declarations -c ../api/boinc_api.cpp -o boinc_api.o
g++ -I../ -I. -I../api -std=gnu++11 -Wno-deprecated-declarations -c ../api/graphics2_util.cpp -o graphics2_util.o
INST=/root/build/brp4-install
rm -rf "$INST"
mkdir -p "$INST/lib" "$INST/include/boinc"
cp boinc.a "$INST/lib/libboinc.a"
ar rcs "$INST/lib/libboinc_api.a" boinc_api.o graphics2_util.o
cp *.h "$INST/include/boinc/"
cp ../api/*.h "$INST/include/boinc/" 2>/dev/null || true
ls -la "$INST/lib"
echo "boinc headers: $(ls "$INST/include/boinc" | wc -l) files"

echo "===== [2] CUDA 12.9 components ====="
cd /tmp
curl -fsSL -o red129.json https://developer.download.nvidia.com/compute/cuda/redist/redistrib_12.9.1.json
pick() { python3 -c "import json;d=json.load(open('/tmp/red129.json'));print(d['$1']['linux-x86_64']['relative_path'])"; }
BASE=https://developer.download.nvidia.com/compute/cuda/redist
rm -rf /tmp/dl /opt/cuda129
mkdir -p /tmp/dl /opt/cuda129
cd /tmp/dl
for comp in cuda_nvcc cuda_cudart libcufft; do
  rel=$(pick $comp)
  echo "== downloading $rel"
  curl -fsSLO "$BASE/$rel"
  tar -xf "$(basename "$rel")" -C /opt/cuda129 --strip-components=1
done
echo "== toolkit layout =="
ls /opt/cuda129/bin/nvcc /opt/cuda129/include/cufft.h 2>&1
ls /opt/cuda129/lib64/ 2>/dev/null | head
ls /opt/cuda129/lib64/libcufft_static.a /opt/cuda129/lib64/libculibos.a 2>&1 || true
ls /opt/cuda129/lib64/stubs/ 2>/dev/null || true
/opt/cuda129/bin/nvcc --version | tail -2
echo "SETUP_DONE"
