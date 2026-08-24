#!/usr/bin/env bash
set -e
REPO="/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port"
BSRC=/root/build/brp4-src-arm64
rm -rf "$BSRC" && mkdir -p "$BSRC"
cp -a "$REPO/src/." "$BSRC/"
cd /root/build && mkdir -p arm64build && cd arm64build
rm -f *.o *.fat einsteinbinary_BRP4_linux_aarch64_cuda_custom
make -f $BSRC/Makefile.linux.cuda.arm64 EINSTEIN_RADIO_SRC=$BSRC \
     CXX=aarch64-linux-gnu-g++-14 NVCC_HOSTCXX=/usr/bin/aarch64-linux-gnu-g++-14 \
     release -j"$(nproc)" > build.log 2>&1 || true
grep -cE ' error|Error [0-9]' build.log || true
tail -n 6 build.log
ls -la einsteinbinary_BRP4_linux_aarch64_cuda_custom 2>/dev/null || exit 1
file einsteinbinary_BRP4_linux_aarch64_cuda_custom | cut -d, -f1-3
