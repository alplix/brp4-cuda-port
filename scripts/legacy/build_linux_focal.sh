#!/usr/bin/env bash
# Builds every Linux binary we ship (modern, kepler, fermi, router, aarch64)
# INSIDE the Ubuntu 20.04 chroot so the glibc floor stays at 2.31.
#   bash scripts/legacy/focal_run.sh bash /repo/scripts/legacy/build_linux_focal.sh
# (create the chroot first with setup_focal_chroot.sh). Outputs land under
# /root/focal/root/... on the host; package.sh picks them up via LROOT=/root/focal.
set -euo pipefail
REPO="${REPO:-/repo}"
B=/root/build
BOINC=$B/3rdparty/boinc-current_brp_apps
SRC=$B/brp4-src
mkdir -p $B/3rdparty

echo "===== [1] BOINC source + native config (glibc 2.31 feature checks) ====="
if [ ! -d "$BOINC" ]; then
  git clone -q --depth 1 -b client_release/8.0/8.0.2 https://github.com/BOINC/boinc "$BOINC"
fi
cd "$BOINC"
if [ ! -f config.h ]; then
  ./_autosetup > /root/boinc_autosetup.log 2>&1
  ./configure --disable-server --disable-client --disable-manager --disable-apps \
    --disable-unit-tests > /root/boinc_configure.log 2>&1
fi

echo "===== [2] BOINC libraries (x86_64) ====="
cd "$BOINC/lib"
sed -i 's|^CC = .*|CC = g++ -I ../ -std=gnu++11 -Wno-deprecated-declarations|' Makefile.linux
sed -i 's|rsa = EVP_PKEY_get0_RSA(pubKey);|rsa = const_cast<RSA *>(EVP_PKEY_get0_RSA(pubKey));|' crypt.cpp
make -f Makefile.linux -j"$(nproc)" > /root/boinc_build.log 2>&1 || { tail -20 /root/boinc_build.log; exit 1; }
g++ -I../ -I. -I../api -std=gnu++11 -Wno-deprecated-declarations -c ../api/boinc_api.cpp -o boinc_api.o
g++ -I../ -I. -I../api -std=gnu++11 -Wno-deprecated-declarations -c ../api/graphics2_util.cpp -o graphics2_util.o
INST=$B/brp4-install
rm -rf "$INST"; mkdir -p "$INST/lib" "$INST/include/boinc"
cp boinc.a "$INST/lib/libboinc.a"
ar rcs "$INST/lib/libboinc_api.a" boinc_api.o graphics2_util.o
cp *.h "$INST/include/boinc/"
cp ../api/*.h "$INST/include/boinc/" 2>/dev/null || true

echo "===== [2b] libxml2 without ICU (focal's libxml2.a would drag in ~30 MB of static ICU) ====="
XV=2.9.14
if [ ! -f $B/xml2-x64/lib/libxml2.a ] || [ ! -f $B/xml2-arm64/lib/libxml2.a ]; then
  cd $B
  [ -f libxml2-$XV.tar.xz ] || curl -fsSLO https://download.gnome.org/sources/libxml2/2.9/libxml2-$XV.tar.xz
  for a in x64 arm64; do
    rm -rf xml2-src-$a && mkdir xml2-src-$a && tar xf libxml2-$XV.tar.xz -C xml2-src-$a --strip-components=1
    ( cd xml2-src-$a
      if [ $a = arm64 ]; then HOSTARGS="--host=aarch64-linux-gnu CC=aarch64-linux-gnu-gcc"; else HOSTARGS=""; fi
      ./configure --prefix=$B/xml2-$a --disable-shared --enable-static --with-pic \
        --without-icu --without-python --without-lzma --without-zlib $HOSTARGS > ../xml2-$a.log 2>&1
      make -j"$(nproc)" >> ../xml2-$a.log 2>&1 && make install >> ../xml2-$a.log 2>&1 )
  done
fi
cp $B/xml2-x64/lib/libxml2.a $B/brp4-install/lib/libxml2.a
mkdir -p $B/brp4-install-arm64/lib
cp $B/xml2-arm64/lib/libxml2.a $B/brp4-install-arm64/lib/libxml2.a
# headers first on the include path (same API, ICU flag off)
export CPPFLAGS_EXTRA="-I$B/xml2-x64/include/libxml2"

echo "===== [3] source sync ====="
mkdir -p "$SRC"
cp -r "$REPO/src/." "$SRC/"
rm -f "$SRC/erp_git_version.h" "$SRC/svn_version.h"

echo "===== [4] linux modern ====="
mkdir -p $B/modern_rebuild && cd $B/modern_rebuild
make -f "$SRC/Makefile.linux.cuda" clean >/dev/null 2>&1 || true
make -f "$SRC/Makefile.linux.cuda" -j"$(nproc)" \
  EINSTEIN_RADIO_SRC="$SRC" EINSTEIN_RADIO_INSTALL=$B/brp4-install BOINC_SRC="$BOINC" \
  NVCC_HOSTCXX=/usr/bin/g++ > $B/modern.log 2>&1 || { tail -30 $B/modern.log; exit 1; }
ls -la einsteinbinary_BRP4_linux_x86_64_modern

echo "===== [5] linux era builds (kepler, fermi) ====="
bash "$REPO/scripts/legacy/build_linux_era.sh" all

echo "===== [6] linux router ====="
rm -rf /root/router_new; mkdir -p /root/router_new
gcc -O2 -Wall -o /root/router_new/einsteinbinary_BRP4_linux_x86_64_router \
  "$REPO/src/launcher/brp4_select.c" -ldl

echo "===== [7] aarch64 (cross, glibc 2.31 sysroot) ====="
export ARM_CXX=aarch64-linux-gnu-g++
bash "$REPO/scripts/arm_boinc.sh"
bash "$REPO/scripts/arm_build.sh"

echo "===== [8] glibc floor of every binary ====="
for f in $B/modern_rebuild/einsteinbinary_BRP4_linux_x86_64_modern \
         $B/era_kepler/einsteinbinary_BRP4_linux_x86_64_kepler \
         $B/era_fermi/einsteinbinary_BRP4_linux_x86_64_fermi \
         /root/router_new/einsteinbinary_BRP4_linux_x86_64_router \
         $B/arm64build/einsteinbinary_BRP4_linux_aarch64_cuda_custom; do
  v=$( (objdump -T "$f" 2>/dev/null; aarch64-linux-gnu-objdump -T "$f" 2>/dev/null) | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -uV | tail -n1)
  echo "$(basename "$f"): max ${v:-none}"
done
echo "LINUX_FOCAL_BUILD_DONE"
