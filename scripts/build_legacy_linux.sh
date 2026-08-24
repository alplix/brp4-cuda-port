#!/usr/bin/env bash
set -e
SRC=/root/build/brp4-src
BUILD=/root/build/legacy118
cp "/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port/src/Makefile.linux.cuda" "$SRC/"
mkdir -p "$SRC/compat"
cp /mnt/c/Users/Alp/Documents/"Default Project"/brp4-cuda-port/src/compat/*.h "$SRC/compat/"
cp "/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port/src/erp_git_version.h" "/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port/src/svn_version.h" "$SRC/"
mkdir -p "$BUILD"
cd "$BUILD"
make -f "$SRC/Makefile.linux.cuda" clean >/dev/null 2>&1 || true
make -f "$SRC/Makefile.linux.cuda" -j8 \
  EINSTEIN_RADIO_SRC="$SRC" \
  CUDA_HOME=/opt/cuda118 \
  NVCC_BIN=/opt/cuda118/bin/nvcc \
  NVCC_HOSTCXX=/usr/bin/x86_64-linux-gnu-g++-11 \
  SASS_ARCHES="35 50 52 61 75 86" \
  PTX_ARCH=35 \
  CUFFT_SHARED=1 \
  TARGET=einsteinbinary_linux_x86_64_cuda118_legacy \
  > /root/legacy_build.log 2>&1 || { tail -20 /root/legacy_build.log; exit 1; }
echo BUILD_OK
ls -la einsteinbinary_linux_x86_64_cuda118_legacy
/opt/cuda118/bin/nvcc --version | head -3 > /dev/null
echo "=== fatbin archs (db.fat) ==="
/opt/cuda129/bin/cuobjdump --list-elf db.fat | grep -oE 'sm_[0-9]+' | sort | uniq -c
/opt/cuda129/bin/cuobjdump db.fat | grep -E 'arch = sm_' | sort | uniq -c
