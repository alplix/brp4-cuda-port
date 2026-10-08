#!/usr/bin/env bash
# Verifies the aarch64 (Jetson) archive on an x86_64 host: fresh extract, glibc
# floor of the ELF, and startup banner + --help under qemu-aarch64 with the stub
# libcuda.so.1 from scripts/legacy/make_libcuda_stub.sh (no GPU run possible here).
# VERSION/DIST select the archive (defaults: v1.3.1, /root/dist_v131).
set -uo pipefail
VERSION="${VERSION:-v1.3.1}"
D="${DIST:-/root/dist_${VERSION//./}}"
MAX_GLIBC="${MAX_GLIBC:-2.31}"
d=/root/vfy_arm64
rm -rf "$d"; mkdir -p "$d"
tar xzf "$D/einsteinbinary_BRP4_linux_aarch64_cuda_custom_${VERSION}.tar.gz" -C "$d" || { echo "FAIL arm64 archive missing"; exit 1; }
exe="$d/einsteinbinary_BRP4_linux_aarch64_cuda_custom"
fail=0
v=$(aarch64-linux-gnu-objdump -T "$exe" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/GLIBC_//' | sort -uV | tail -n1)
if [ -n "$v" ] && [ "$(printf "%s\n%s\n" "$v" "$MAX_GLIBC" | sort -V | tail -n1)" != "$MAX_GLIBC" ]; then
  echo "FAIL arm64 glibc floor: needs $v (limit $MAX_GLIBC)"; fail=1
else
  echo "ok   arm64 glibc floor: max ${v:-none} (limit $MAX_GLIBC)"
fi
Q=$(ls /usr/libexec/qemu-binfmt/*/qemu-aarch64 /usr/bin/qemu-aarch64 2>/dev/null | head -n1)
( cd "$d" && "$Q" -L /usr/aarch64-linux-gnu "$exe" --help > q.log 2>&1 ); rc=$?
if [ $rc -eq 0 ] && grep -q "BRP4 CUDA port ${VERSION}" "$d/q.log"; then
  echo "PASS arm64: banner ${VERSION} present, --help exits 0 (qemu-aarch64)"
else
  echo "FAIL arm64 (rc=$rc)"; head -5 "$d/q.log"; fail=1
fi
[ $fail -eq 0 ] && echo ALL_ARM64_GREEN
exit $fail
