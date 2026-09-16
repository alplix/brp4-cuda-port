#!/usr/bin/env bash
# Linux x86_64 modern build inside WSL: syncs the repository's src/ tree into the
# WSL build tree and runs Makefile.linux.cuda (see scripts/README.md for the layout).
set -euo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC=/root/build/brp4-src
mkdir -p "$SRC"
cp -r "$REPO/src/." "$SRC/"
rm -f "$SRC/erp_git_version.h" "$SRC/svn_version.h"
cd "$SRC"
make -f Makefile.linux.cuda clean >/dev/null 2>&1 || true
make -f Makefile.linux.cuda -j"$(nproc)" \
  EINSTEIN_RADIO_SRC="$SRC" \
  EINSTEIN_RADIO_INSTALL=/root/build/brp4-install \
  BOINC_SRC=/root/build/3rdparty/boinc-current_brp_apps "$@"
ls -la "$SRC"/einsteinbinary_BRP4_linux_x86_64_modern
