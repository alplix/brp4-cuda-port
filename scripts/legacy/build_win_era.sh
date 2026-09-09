#!/usr/bin/env bash
# Builds the legacy-era WINDOWS x64 binaries by cross-compiling from WSL:
#   - device fatbins: era Linux nvcc (device images are OS-agnostic)
#   - host code: x86_64-w64-mingw32-g++ (same recipe as the ARM64 win build)
#   - nvcuda/cufft imports: COFF import libs built by make_nvcuda_import.sh
#     (nvcuda) and the era DLL export tables (cufft)
# Requires: provision_env.sh, provision_win_x64.sh, make_nvcuda_import.sh,
#           setup_legacy_toolchains.sh, and the extracted era cufft DLLs
#           (extract_cufft_windows.sh).
set -euo pipefail
REPO=/mnt/c/Users/Alp/.zcode/workspace/default/brp4-cuda-port
SRC=/root/build/brp4-src
IMPORTS=/root/wx/imports
# full source sync (makefile, all .c/.cpp/.h, cuda/, compat/)
mkdir -p "$SRC"
cp -r "$REPO/src/." "$SRC/"
rm -f "$SRC/erp_git_version.h" "$SRC/svn_version.h"

build_era_win() { # $1=flavor $2=cuda_home $3=sass $4=ptx $5=target $6=nvcc_extra $7=cufft_lib $8=cufft_dll
  local flavor=$1 cuda=$2 sass=$3 ptx=$4 target=$5 extra=$6 cufftlib=$7 cufftdll=$8
  # era-appropriate nvcc host parser (device-only fatbin, Linux nvcc):
  # CUDA 10.2 pairs with gcc 8.3, CUDA 8.0 with gcc 5.x + era glibc headers
  local hostcxx=/opt/gcc8-bin/g++
  if [ "$cuda" = "/opt/cuda80" ]; then
    hostcxx=/opt/gcc5-bin/g++
    extra="$extra -I/opt/gcc5-root/usr/include -I/opt/gcc5-root/usr/include/x86_64-linux-gnu"
  elif [ "$cuda" = "/opt/cuda129" ]; then
    hostcxx=/usr/bin/x86_64-linux-gnu-g++-14
  fi
  echo "===== building win/$flavor (CUDA $cuda, SASS $sass + PTX $ptx) ====="
  rm -rf "/root/build/wera_$flavor"
  mkdir -p "/root/build/wera_$flavor"
  rm -f "$SRC/erp_git_version.h"
  cd "/root/build/wera_$flavor"
  make -f "$SRC/Makefile.win64.cuda" clean >/dev/null 2>&1 || true
  make -f "$SRC/Makefile.win64.cuda" -j8 \
    EINSTEIN_RADIO_SRC="$SRC" \
    EINSTEIN_RADIO_INSTALL=/root/wx/brp4-install-win \
    BOINC_SRC=/root/build/3rdparty/boinc-current_brp_apps \
    CUDA_HOME="$cuda" \
    CUFFT_INC="$cuda/include" \
    CUFFT_LIB="$cufftlib" \
    NVCUDA_LIB="$IMPORTS/libnvcuda.a" \
    WIN_DEPS_LIB=/root/wx/deps/lib \
    WIN_DEPS_INC="/root/wx/deps/include /root/wx/deps/include/libxml2" \
    CXX=x86_64-w64-mingw32-g++ \
    NVCC_BIN="$cuda/bin/nvcc" \
    MSVC_BIN="$hostcxx" \
    SASS_ARCHES="$sass" \
    PTX_ARCH="$ptx" \
    NVCC_EXTRA="$extra" \
    ERP_VERSION=v1.2 \
    BUILD_FLAVOR="-$flavor" \
    TARGET="$target" > "/root/build/wera_${flavor}.log" 2>&1 || {
      echo "WIN BUILD FAILED - tail of wera_${flavor}.log:"; tail -30 "/root/build/wera_${flavor}.log"; exit 1; }
  echo "== win/$flavor BUILD_OK"
  ls -la "$target"
  "$T-objdump" -p "$target" 2>/dev/null | grep -A3 "DLL Name" | head -12 || true
}

T=x86_64-w64-mingw32
case "${1:-all}" in
  modern)
    build_era_win modern /opt/cuda129 "50 61 75 86 89 90 100f 120f" 50 \
      einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe \
      "-U_GNU_SOURCE -U_FORTIFY_SOURCE --allow-unsupported-compiler" \
      "$IMPORTS/libcufft64_11.a" cufft64_11.dll
    ;;
  kepler)
    build_era_win kepler /opt/cuda102 "30 35 37" 35 \
      einsteinbinary_BRP4_windows_x86_64_cuda102_kepler.exe \
      "-U_GNU_SOURCE -U_FORTIFY_SOURCE -D__HAVE_FLOAT128=0" \
      "$IMPORTS/libcufft64_10.a" cufft64_10.dll
    ;;
  fermi)
    build_era_win fermi /opt/cuda80 "20" 20 \
      einsteinbinary_BRP4_windows_x86_64_cuda80_fermi.exe \
      "-U_GNU_SOURCE -U_FORTIFY_SOURCE -D__HAVE_FLOAT128=0" \
      "$IMPORTS/libcufft64_80.a" cufft64_80.dll
    ;;
  all)
    build_era_win kepler /opt/cuda102 "30 35 37" 35 \
      einsteinbinary_BRP4_windows_x86_64_cuda102_kepler.exe \
      "-U_GNU_SOURCE -U_FORTIFY_SOURCE -D__HAVE_FLOAT128=0" \
      "$IMPORTS/libcufft64_10.a" cufft64_10.dll
    build_era_win fermi /opt/cuda80 "20" 20 \
      einsteinbinary_BRP4_windows_x86_64_cuda80_fermi.exe \
      "-U_GNU_SOURCE -U_FORTIFY_SOURCE -D__HAVE_FLOAT128=0" \
      "$IMPORTS/libcufft64_80.a" cufft64_80.dll
    ;;
  *) echo "usage: $0 [kepler|fermi|all]"; exit 2;;
esac
echo "LEGACY_WIN_BUILDS_DONE"
