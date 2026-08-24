#!/usr/bin/env bash
Q=$(ls /usr/libexec/qemu-binfmt/*/qemu-aarch64 /usr/bin/qemu-aarch64 2>/dev/null | head -n1)
echo "Q=$Q"
cd /root/build/arm64build
LD_LIBRARY_PATH=/opt/cuda129-arm64/root/lib/stubs "$Q" -L /usr/aarch64-linux-gnu ./einsteinbinary_BRP4_linux_aarch64_cuda_custom --help > q.log 2>&1
echo "exit=$?"
head -8 q.log
