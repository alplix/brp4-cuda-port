#!/usr/bin/env bash
# Installs the legacy CUDA toolchains from the runfiles downloaded by
# download_toolchains.sh, and relaxes their gcc version gates so the
# device-only (-fatbin) builds accept a modern host gcc.
#   CUDA 10.2 -> /opt/cuda102  (Kepler: last toolkit with sm_30)
#   CUDA 8.0  -> /opt/cuda80   (Fermi: last toolkit with sm_20/21)
set -euo pipefail
DL=/root/dl_legacy

# ancient CUDA installers link libxml2.so.2 (dropped after Ubuntu 20.04-ish);
# provide the old soname via a jammy deb extract
bash /mnt/c/Users/Alp/.zcode/workspace/default/brp4-cuda-port/scripts/legacy/setup_xml2_compat.sh
export LD_LIBRARY_PATH=/root/xml2compat/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

install_cuda() { # $1=runfile $2=dest $3=extra flags
  local run="$DL/$1" dest="$2" extra="${3:-}"
  if [ -x "$dest/bin/nvcc" ]; then echo "== SKIP $dest (already installed)"; return 0; fi
  if [ ! -f "$run" ]; then echo "== DEFER $1 (not downloaded yet)"; return 0; fi
  echo "== installing $1 -> $dest"
  chmod +x "$run"
  # the 10.x installer cannot parse two-digit gcc versions and only uses gcc
  # --version for a validation printout; feed it a single-digit answer
  mkdir -p /root/fakebin
  printf '#!/bin/sh\necho "gcc (compat-shim) 8.5.0"\n' > /root/fakebin/gcc
  chmod +x /root/fakebin/gcc
  PATH=/root/fakebin:$PATH "$run" --silent --toolkit --toolkitpath="$dest" --no-opengl-libs $extra
}

install_cuda cuda102_linux.run /opt/cuda102 --no-man-page
install_cuda cuda80_linux.run  /opt/cuda80

patch_host_config() { # $1=toolkit dir
  # the gcc gate can sit in include/host_config.h or include/crt/host_config.h
  # depending on the CUDA generation; patch whichever exists
  local found=0
  for f in "$1/include/host_config.h" "$1/include/crt/host_config.h"; do
    if [ -f "$f" ]; then
      # device-only fatbin builds never invoke the host compiler for codegen,
      # so raising the gcc gate is safe; nvcc only uses it for header parsing
      sed -i -E 's/#if __GNUC__ > ([0-9]+)/#if __GNUC__ > 99/' "$f"
      found=1
    fi
  done
  if [ $found -eq 1 ]; then
    echo "== patched gcc gate in $1"
  else
    echo "== DEFER patch $1 (toolkit not installed)"
  fi
}
patch_host_config /opt/cuda102
patch_host_config /opt/cuda80

echo "== static cuFFT presence =="
ls -la /opt/cuda102/lib64/libcufft_static*.a 2>&1 || true
ls -la /opt/cuda80/lib64/libcufft_static*.a 2>&1 || true
ls -la /opt/cuda80/lib64/libculibos.a /opt/cuda102/lib64/libculibos.a 2>&1 || true
[ -x /opt/cuda102/bin/nvcc ] && /opt/cuda102/bin/nvcc --version | tail -2 || true
[ -x /opt/cuda80/bin/nvcc ] && /opt/cuda80/bin/nvcc --version | tail -2 || true
echo "LEGACY_TOOLCHAINS_DONE (check DEFER lines for anything pending)"
