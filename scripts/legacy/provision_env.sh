#!/usr/bin/env bash
# Full WSL environment provisioning for the BRP4 CUDA port builds.
# Rebuilds everything a fresh WSL needs: apt deps, BOINC source+libs,
# CUDA 12.9 redist components, cross-mingw for the Windows x86_64 builds.
set -euo pipefail

echo "===== [0] apt packages ====="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential autoconf automake libtool pkg-config \
  git curl python3 p7zip-full xz-utils \
  libgsl-dev libfftw3-dev libxml2-dev zlib1g-dev libssl-dev \
  liblzma-dev libzstd-dev binutils-dev libiberty-dev \
  g++-mingw-w64-x86-64-posix g++-mingw-w64-x86-64 \
  > /dev/null
# a g++ old enough for nvcc header parsing (12.9 supports up to gcc 14)
if apt-cache show g++-14 >/dev/null 2>&1; then
  apt-get install -y -qq g++-14 > /dev/null || true
fi
g++ --version | head -1
x86_64-w64-mingw32-g++ --version | head -1 || true

echo "===== [1] BOINC checkout ====="
mkdir -p /root/build/3rdparty
cd /root/build/3rdparty
if [ ! -d boinc-current_brp_apps ]; then
  git clone -q --depth 1 -b client_release/8.0/8.0.2 https://github.com/BOINC/boinc boinc-current_brp_apps
fi
cd boinc-current_brp_apps
if [ ! -f config.h ]; then
  ./_autosetup > /root/boinc_autosetup.log 2>&1
  ./configure --disable-server --disable-client --disable-manager --disable-apps \
    --disable-unit-tests > /root/boinc_configure.log 2>&1
fi

echo "===== [2] BOINC libraries ====="
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
echo "boinc headers: $(ls "$INST/include/boinc" | wc -l) files"

echo "===== [3] CUDA 12.9 components ====="
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
/opt/cuda129/bin/nvcc --version | tail -2

echo "===== [4] cross-mingw sanity ====="
x86_64-w64-mingw32-g++ --version | head -1
x86_64-w64-mingw32-dlltool --version | head -1 || echo "no dlltool (will hand-write .def)"

echo "PROVISION_DONE"
