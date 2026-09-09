#!/usr/bin/env bash
# Installs the CUDA 8.0 toolkit from the inner payload runfile (the outer
# installer ignores double-dash flags and silently no-ops on modern distros).
set -euo pipefail
[ -x /opt/cuda80/bin/nvcc ] && { echo "== SKIP /opt/cuda80 (already installed)"; exit 0; }

if [ ! -f /root/dl80x/cuda-linux64-rel-8.0.61-21551265.run ]; then
  mkdir -p /root/dl80x
  LD_LIBRARY_PATH=/root/xml2compat/usr/lib/x86_64-linux-gnu \
    sh /root/dl_legacy/cuda80_linux.run --extract=/root/dl80x >/root/dl80x/extract.log 2>&1
fi

rm -rf /opt/cuda80 && mkdir -p /opt/cuda80
# modern perl dropped '.' from @INC, so extract the makeself payload manually
# and run install-linux.pl with PERL5LIB pointing at its own directory
INNER=/root/dl80x/inner
rm -rf "$INNER" && mkdir -p "$INNER"
# makeself's --target extracts AND runs the embedded (perl) installer, which
# dies on modern perl ('.' removed from @INC); tolerate that exit code, the
# extracted files are what we actually want
sh /root/dl80x/cuda-linux64-rel-8.0.61-21551265.run --target "$INNER" \
  > "$INNER/extract.log" 2>&1 || true
ls "$INNER" | head -10
[ -f "$INNER/install-linux.pl" ] || { echo "install-linux.pl not extracted"; exit 1; }

mkdir -p /root/fakebin
printf '#!/bin/sh\necho "gcc (compat-shim) 5.4.0"\n' > /root/fakebin/gcc
chmod +x /root/fakebin/gcc
export LD_LIBRARY_PATH=/root/xml2compat/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export PATH=/root/fakebin:$PATH

cd "$INNER"
find "$INNER" -name InstallUtils.pm -exec dirname {} \; | head -1 > /tmp/iu_dir
IU_DIR=$(cat /tmp/iu_dir)
[ -n "$IU_DIR" ] || { echo "InstallUtils.pm not found in payload"; ls -la "$INNER"; exit 1; }
PERL5LIB="$IU_DIR" perl "$IU_DIR/install-linux.pl" -prefix=/opt/cuda80 -noprompt \
  > "$INNER/install.log" 2>&1 || { tail -15 "$INNER/install.log"; exit 1; }

ls /opt/cuda80/bin/nvcc || { echo "nvcc still missing"; tail -20 /root/dl80x/install.log; exit 1; }
echo "== cuda80 toolkit installed"

# patch the gcc gate (CUDA 8: include/host_config.h)
for f in /opt/cuda80/include/host_config.h /opt/cuda80/include/crt/host_config.h; do
  if [ -f "$f" ]; then
    sed -i -E 's/#if __GNUC__ > ([0-9]+)/#if __GNUC__ > 99/' "$f"
    echo "== patched $f"
  fi
done
/opt/cuda80/bin/nvcc --version | tail -2
echo CUDA80_READY
