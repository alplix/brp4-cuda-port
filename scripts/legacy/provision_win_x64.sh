#!/usr/bin/env bash
# Provisions static dependencies + BOINC libraries for the WINDOWS x86_64
# cross builds (x86_64-w64-mingw32 from WSL). Adapted from the proven
# wa_deps.sh / wa_boinc.sh (Windows-ARM64) recipes.
set -e
T=x86_64-w64-mingw32
P=/root/wx/deps
REPO=/mnt/c/Users/Alp/.zcode/workspace/default/brp4-cuda-port
mkdir -p $P /root/wx/src && cd /root/wx/src

dl() { [ -s "$1" ] || curl -fsSL "$2" -o "$1"; }

echo "=== zlib ==="
dl zlib-1.3.1.tar.gz https://zlib.net/fossils/zlib-1.3.1.tar.gz
rm -rf zlib-1.3.1 && tar xf zlib-1.3.1.tar.gz && cd zlib-1.3.1
CC=$T-gcc AR="$T-ar" RANLIB=$T-ranlib ./configure --static --prefix=$P
make -j$(nproc) > /root/wx/zlib.log 2>&1 && make install >/dev/null && cd ..

echo "=== iconv ==="
dl libiconv-1.17.tar.gz https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
rm -rf libiconv-1.17 && tar xf libiconv-1.17.tar.gz && cd libiconv-1.17
./configure --host=$T --enable-static --disable-shared --prefix=$P >/dev/null 2>&1
make -j$(nproc) >/dev/null 2>&1 && make install >/dev/null && cd ..

echo "=== xml2 ==="
dl libxml2-2.11.9.tar.xz https://download.gnome.org/sources/libxml2/2.11/libxml2-2.11.9.tar.xz
rm -rf libxml2-2.11.9 && tar xf libxml2-2.11.9.tar.xz && cd libxml2-2.11.9
./configure --host=$T --enable-static --disable-shared --prefix=$P \
  --without-lzma --without-python --with-zlib=$P --with-iconv=$P \
  --without-debug --without-threads >/dev/null 2>&1
make -j$(nproc) >/dev/null 2>&1 && make install >/dev/null && cd ..

echo "=== gsl ==="
dl gsl-2.8.tar.gz https://ftp.gnu.org/gnu/gsl/gsl-2.8.tar.gz
rm -rf gsl-2.8 && tar xf gsl-2.8.tar.gz && cd gsl-2.8
./configure --host=$T --enable-static --disable-shared --prefix=$P >/dev/null 2>&1
make -j$(nproc) >/dev/null 2>&1 && make install >/dev/null && cd ..

echo "=== fftw3f ==="
dl fftw-3.3.10.tar.gz https://www.fftw.org/fftw-3.3.10.tar.gz
rm -rf fftw-3.3.10 && tar xf fftw-3.3.10.tar.gz && cd fftw-3.3.10
./configure --host=$T --enable-float --enable-static --disable-shared --prefix=$P \
  --with-our-malloc \
  --enable-sse2 --disable-avx --disable-avx2 --disable-avx512 > /root/wx/fftw_conf.log 2>&1 || {
  echo "fftw configure FAILED:"; tail -15 /root/wx/fftw_conf.log; exit 1; }
make -j$(nproc) > /root/wx/fftw.log 2>&1 && make install >/dev/null && cd ..

echo "=== done deps ==="
ls $P/lib/*.a | head -12

echo "=== BOINC libraries (x86_64-w64-mingw32) ==="
SRC=/root/build/3rdparty/boinc-current_brp_apps
INST=/root/wx/brp4-install-win
mkdir -p $INST/lib $INST/include/boinc /root/wx
cp "$REPO/src/compat/mingw_str_shim.h" /root/wx/inc_shim.h
XF_CPP='CPPFLAGS=-I/root/wx -I../win_build -I.. -I../api -include /root/wx/inc_shim.h -DHAVE_STRCASECMP=1 -DHAVE_STRNCASECMP=1'
XF_CXX='CXXFLAGS=-O2 -DNDEBUG -w -std=gnu++14'
cd $SRC/lib
make -f Makefile.mingw MINGW=$T clean >/dev/null 2>&1 || true
make -f Makefile.mingw MINGW=$T libboinc.a -j$(nproc) "$XF_CPP" "$XF_CXX" > /root/wx/boinc_mingw.log 2>&1 || {
  echo "BOINC libboinc.a FAILED:"; tail -25 /root/wx/boinc_mingw.log; exit 1; }
cd $SRC/api
$T-g++ -O2 -DNDEBUG -w -std=gnu++14 -I/root/wx -I../win_build -I.. -I../api -I../lib -include /root/wx/inc_shim.h -c boinc_api.cpp -o boinc_api.o
$T-g++ -O2 -DNDEBUG -w -std=gnu++14 -I/root/wx -I../win_build -I.. -I../api -I../lib -include /root/wx/inc_shim.h -c graphics2_util.cpp -o graphics2_util.o
$T-ar rcs libboinc_api.a boinc_api.o graphics2_util.o

cp $SRC/lib/libboinc.a $SRC/api/libboinc_api.a $INST/lib/
cp $SRC/version.h* $INST/include/boinc/ 2>/dev/null || true
cp $SRC/svn_version.h* $INST/include/boinc/ 2>/dev/null || true
cp $SRC/win_build/config.h $INST/include/boinc/
for h in app_ipc boinc_win url common_defs diagnostics diagnostics_win error_numbers \
         filesys hostinfo proxy_info prefs miofile mfile parse util coproc \
         str_util wslinfo base64; do cp $SRC/lib/$h.h $INST/include/boinc/ 2>/dev/null || true; done
for h in boinc_api boinc_opencl graphics2 graphics2_util; do cp $SRC/api/$h.h $INST/include/boinc/ 2>/dev/null || true; done
cp $SRC/lib/*.h $INST/include/boinc/ 2>/dev/null || true
echo "--- built:"
ls -la $INST/lib/
file $INST/lib/libboinc.a | cut -d, -f1-3
echo "WIN_X64_PROVISION_DONE"
