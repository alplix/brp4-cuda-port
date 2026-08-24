#!/usr/bin/env bash
set -e
export PATH=/opt/llvm-mingw/bin:$PATH
T=aarch64-w64-mingw32
P=/root/wa/deps
cd /root/wa/src/zlib-1.3.1
make clean >/dev/null 2>&1 || true
CC=$T-gcc AR=$T-ar RANLIB=$T-ranlib ./configure --static --prefix=$P >/dev/null
make -j$(nproc) >/dev/null && make install >/dev/null
ls -la $P/lib/libz.a
$T-nm $P/lib/libz.a 2>/dev/null | grep -c " T inflate" || true
