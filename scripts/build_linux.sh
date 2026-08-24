#!/usr/bin/env bash
set -e
SRC=/root/build/brp4-src
cp "/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port/src/Makefile.linux.cuda" "$SRC/"
mkdir -p "$SRC/compat"
cp /mnt/c/Users/Alp/Documents/"Default Project"/brp4-cuda-port/src/compat/*.h "$SRC/compat/"
cp "/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port/src/erp_git_version.h" "/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port/src/svn_version.h" "$SRC/"
cd "$SRC"
make -f Makefile.linux.cuda clean >/dev/null 2>&1 || true
make -f Makefile.linux.cuda -j8 2>&1 | tail -25
echo BUILD_EXIT=$?
ls -la "$TARGET" 2>/dev/null || ls -la /root/build/brp4-src/einsteinbinary_linux_x86_64_cuda_custom 2>/dev/null || true
