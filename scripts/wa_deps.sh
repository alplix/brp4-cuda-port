#!/usr/bin/env bash
set -e
export PATH=/opt/llvm-mingw/bin:$PATH
T=aarch64-w64-mingw32
P=/root/wa/deps
mkdir -p $P /root/wa/src && cd /root/wa/src

dl() { [ -s "$1" ] || curl -fsSL "$2" -o "$1"; }

echo "=== zlib ==="
dl zlib-1.3.1.tar.gz https://zlib.net/fossils/zlib-1.3.1.tar.gz
tar xf zlib-1.3.1.tar.gz && cd zlib-1.3.1
CC=$T-gcc AR="llvm-ar rc" RANLIB=llvm-ranlib ./configure --static --prefix=$P >/dev/null
make -j$(nproc) >/dev/null && make install >/dev/null && cd ..

echo "=== iconv ==="
dl libiconv-1.17.tar.gz https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
tar xf libiconv-1.17.tar.gz && cd libiconv-1.17
./configure --host=$T --enable-static --disable-shared --prefix=$P >/dev/null 2>&1
make -j$(nproc) >/dev/null 2>&1 && make install >/dev/null && cd ..

echo "=== xml2 ==="
dl libxml2-2.11.9.tar.xz https://download.gnome.org/sources/libxml2/2.11/libxml2-2.11.9.tar.xz
tar xf libxml2-2.11.9.tar.xz && cd libxml2-2.11.9
./configure --host=$T --enable-static --disable-shared --prefix=$P \
  --without-lzma --without-python --with-zlib=$P --with-iconv=$P \
  --without-debug --without-threads >/dev/null 2>&1
make -j$(nproc) >/dev/null 2>&1 && make install >/dev/null && cd ..

echo "=== gsl ==="
dl gsl-2.8.tar.gz https://ftp.gnu.org/gnu/gsl/gsl-2.8.tar.gz
tar xf gsl-2.8.tar.gz && cd gsl-2.8
./configure --host=$T --enable-static --disable-shared --prefix=$P >/dev/null 2>&1
make -j$(nproc) >/dev/null 2>&1 && make install >/dev/null && cd ..

echo "=== fftw3f ==="
dl fftw-3.3.10.tar.gz https://www.fftw.org/fftw-3.3.10.tar.gz
tar xf fftw-3.3.10.tar.gz && cd fftw-3.3.10
./configure --host=$T --enable-float --enable-static --disable-shared --prefix=$P \
  --disable-sse2 --disable-avx --disable-avx2 --disable-avx512 >/dev/null 2>&1
make -j$(nproc) >/dev/null 2>&1 && make install >/dev/null && cd ..

echo "=== done deps ==="
ls $P/lib/*.a | head -12
