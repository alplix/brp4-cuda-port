#!/usr/bin/env bash
# Builds the legacy-era Linux x86_64 binaries:
#   kepler : CUDA 10.2, SASS sm_30/35/37 + compute_35 PTX  (GTX 600/700, GT 7xx, Titan)
#   fermi  : CUDA 8.0,  SASS sm_20/21   + compute_20 PTX  (GTX 400/500, GT 610/620/630)
# Requires: provision_env.sh, setup_legacy_toolchains.sh (downloads done first).
set -euo pipefail
REPO=/mnt/c/Users/Alp/.zcode/workspace/default/brp4-cuda-port
SRC=/root/build/brp4-src
# full source sync (makefile, all .c/.cpp/.h, cuda/, compat/)
mkdir -p "$SRC"
cp -r "$REPO/src/." "$SRC/"
rm -f "$SRC/erp_git_version.h" "$SRC/svn_version.h"

build_era() { # $1=flavor $2=cuda_home $3=sass $4=ptx $5=target $6=nvcc_extra [$7=hostcxx]
  local flavor=$1 cuda=$2 sass=$3 ptx=$4 target=$5 extra=$6
  # era-appropriate nvcc host parser: CUDA 10.2 pairs with gcc 8.3, CUDA 8.0 with gcc 5.x
  local hostcxx=${7:-}
  if [ -z "$hostcxx" ]; then
    case "$cuda" in
      /opt/cuda80) hostcxx=/opt/gcc5-bin/g++;;
      *)           hostcxx=/opt/gcc8-bin/g++;;
    esac
  fi
  echo "===== building $flavor (CUDA at $cuda, SASS $sass + PTX $ptx, host $hostcxx) ====="
  rm -rf "/root/build/era_$flavor"
  mkdir -p "/root/build/era_$flavor"
  rm -f "$SRC/erp_git_version.h"
  cd "/root/build/era_$flavor"
  make -f "$SRC/Makefile.linux.cuda" clean >/dev/null 2>&1 || true
  make -f "$SRC/Makefile.linux.cuda" -j8 \
    EINSTEIN_RADIO_SRC="$SRC" \
    EINSTEIN_RADIO_INSTALL=/root/build/brp4-install \
    BOINC_SRC=/root/build/3rdparty/boinc-current_brp_apps \
    CUDA_HOME="$cuda" \
    NVCC_BIN="$cuda/bin/nvcc" \
    NVCC_HOSTCXX="$hostcxx" \
    SASS_ARCHES="$sass" \
    PTX_ARCH="$ptx" \
    NVCC_EXTRA="$extra" \
    CUFFT_SHARED=1 \
    CUDA_LIBDIR=lib64 \
    ERP_VERSION=v1.2 \
    BUILD_FLAVOR="-$flavor" \
    TARGET="$target" > "/root/build/era_${flavor}.log" 2>&1 || {
      echo "BUILD FAILED - tail of era_${flavor}.log:"; tail -30 "/root/build/era_${flavor}.log"; exit 1; }
  echo "== $flavor BUILD_OK"
  ls -la "$target"
  "$cuda/bin/cuobjdump" --list-elf db.fat | grep -oE 'sm_[0-9]+' | sort | uniq -c || true
  "$cuda/bin/cuobjdump" --list-ptx db.fat | grep -oE 'compute_[0-9]+' | sort | uniq -c || true
}

case "${1:-all}" in
  kepler)
    build_era kepler /opt/cuda102 "30 35 37" 35 \
      einsteinbinary_BRP4_linux_x86_64_kepler \
      "-U_GNU_SOURCE -U_FORTIFY_SOURCE -D__HAVE_FLOAT128=0"
    ;;
  fermi)
    build_era fermi /opt/cuda80 "20" 20 \
      einsteinbinary_BRP4_linux_x86_64_fermi \
      "-U_GNU_SOURCE -U_FORTIFY_SOURCE -D__HAVE_FLOAT128=0 -I/opt/gcc5-root/usr/include -I/opt/gcc5-root/usr/include/x86_64-linux-gnu"
    ;;
  all)
    build_era kepler /opt/cuda102 "30 35 37" 35 \
      einsteinbinary_BRP4_linux_x86_64_kepler \
      "-U_GNU_SOURCE -U_FORTIFY_SOURCE -D__HAVE_FLOAT128=0"
    build_era fermi /opt/cuda80 "20" 20 \
      einsteinbinary_BRP4_linux_x86_64_fermi \
      "-U_GNU_SOURCE -U_FORTIFY_SOURCE -D__HAVE_FLOAT128=0 -I/opt/gcc5-root/usr/include -I/opt/gcc5-root/usr/include/x86_64-linux-gnu"
    ;;
  *) echo "usage: $0 [kepler|fermi|all]"; exit 2;;
esac
echo "LEGACY_LINUX_BUILDS_DONE"
