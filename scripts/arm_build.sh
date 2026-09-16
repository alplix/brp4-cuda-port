#!/usr/bin/env bash
set -e
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BSRC=/root/build/brp4-src-arm64
rm -rf "$BSRC" && mkdir -p "$BSRC"
cp -a "$REPO/src/." "$BSRC/"
# force regeneration of the version banner: the checked-in erp_git_version.h
# is a stale placeholder, and the Makefile rule only fires when it's missing
# (every other build script deletes it first for the same reason)
rm -f "$BSRC/erp_git_version.h" "$BSRC/svn_version.h"
cd /root/build && mkdir -p arm64build && cd arm64build
rm -f *.o *.fat einsteinbinary_BRP4_linux_aarch64_cuda_custom
make -f $BSRC/Makefile.linux.cuda.arm64 EINSTEIN_RADIO_SRC=$BSRC \
     CXX=aarch64-linux-gnu-g++-14 NVCC_HOSTCXX=/usr/bin/aarch64-linux-gnu-g++-14 \
     release -j"$(nproc)" > build.log 2>&1 || true
grep -cE ' error|Error [0-9]' build.log || true
tail -n 6 build.log
ls -la einsteinbinary_BRP4_linux_aarch64_cuda_custom 2>/dev/null || exit 1
file einsteinbinary_BRP4_linux_aarch64_cuda_custom | cut -d, -f1-3
