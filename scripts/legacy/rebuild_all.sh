#!/usr/bin/env bash
# Full rebuild chain after the v1.2 renaming + banner change:
# relink modern/era builds with new target names, rebuild both routers,
# then assemble all 8 packages.
set -euo pipefail
REPO=/mnt/c/Users/Alp/.zcode/workspace/default/brp4-cuda-port
SRC=/root/build/brp4-src

echo "===== sync sources ====="
cp -r "$REPO/src/." "$SRC/"
rm -f "$SRC/erp_git_version.h" "$SRC/svn_version.h"

echo "===== [1] linux modern relink (new default target) ====="
cd /root/build/modern_rebuild
make -f "$SRC/Makefile.linux.cuda" clean >/dev/null 2>&1 || true
make -f "$SRC/Makefile.linux.cuda" -j8 \
  EINSTEIN_RADIO_SRC="$SRC" \
  EINSTEIN_RADIO_INSTALL=/root/build/brp4-install \
  BOINC_SRC=/root/build/3rdparty/boinc-current_brp_apps \
  ERP_VERSION=v1.2 > /root/build/modern.log 2>&1 || { tail -20 /root/build/modern.log; exit 1; }
ls -la einsteinbinary_BRP4_linux_x86_64_modern

echo "===== [2] linux era builds ====="
bash "$REPO/scripts/legacy/build_linux_era.sh" all

echo "===== [3] windows era builds ====="
bash "$REPO/scripts/legacy/build_win_era.sh" all

echo "===== [4] routers ====="
rm -f /root/router_new
mkdir -p /root/router_new
gcc -O2 -Wall -o /root/router_new/einsteinbinary_BRP4_linux_x86_64_router \
  "$REPO/src/launcher/brp4_select.c" -ldl
gcc -O2 -Wall -o /root/winrouter/einsteinbinary_BRP4_windows_x86_64_router.exe \
  "$REPO/src/launcher/brp4_select.c"
echo "REBUILD_CHAIN_DONE"
