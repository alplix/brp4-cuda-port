#!/usr/bin/env bash
# Windows half of the release build (cross-compiled from the normal WSL host):
# the three era executables plus the PE router. The Linux half lives in
# build_linux_focal.sh (Ubuntu 20.04 chroot) - rebuild_all.sh still does both
# on the host for quick experiments, but releases use these two scripts.
set -euo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
bash "$REPO/scripts/legacy/build_win_era.sh" all
mkdir -p /root/winrouter
x86_64-w64-mingw32-gcc -O2 -Wall -o /root/winrouter/einsteinbinary_BRP4_windows_x86_64_router.exe \
  "$REPO/src/launcher/brp4_select.c"
file /root/winrouter/einsteinbinary_BRP4_windows_x86_64_router.exe
echo "WINDOWS_BUILD_DONE"
