#!/usr/bin/env bash
# Sidecar gcc toolchains (extracted, not installed) for the legacy nvcc
# frontends: their 2016/2019 EDG parsers cannot handle modern libstdc++
# headers, so the fatbin builds parse headers against an era-matched gcc.
#   ./setup_gcc_sidecar.sh 8  -> gcc 8.3 (for nvcc CUDA 10.2)  -> /opt/gcc8-bin
#   ./setup_gcc_sidecar.sh 5  -> gcc 5.4 (for nvcc CUDA 8.0)   -> /opt/gcc5-bin
# nvcc only preprocesses/parses with it (device-only -fatbin), so a plain
# dpkg -x unpack of Ubuntu archive debs is safe.
set -euo pipefail
VER="${1:-8}"
if [ "$VER" = "8" ]; then
  VER_SFX=8;  BIN=/opt/gcc8-bin; ROOT=/opt/gcc8-root
  POOL=https://old-releases.ubuntu.com/ubuntu/pool/main/g/gcc-8
  PAT_REL='8\.3\.0-6ubuntu1[^"~]*'      # disco build, no ~ suffixed dupes
  ISL=https://old-releases.ubuntu.com/ubuntu/pool/main/i/isl/libisl19_0.20-2_amd64.deb
elif [ "$VER" = "5" ]; then
  VER_SFX=5;  BIN=/opt/gcc5-bin; ROOT=/opt/gcc5-root
  POOL=https://old-releases.ubuntu.com/ubuntu/pool/main/g/gcc-5
  PAT_REL='5\.[45]\.[0-9][^"~]*'        # wily/artful builds (5.4.1/5.5.0)
  ISL=https://old-releases.ubuntu.com/ubuntu/pool/main/i/isl/libisl15_0.17.1-1_amd64.deb
else
  echo "usage: $0 [5|8]"; exit 2
fi

if [ -x "$BIN/g++" ]; then echo "== SKIP gcc$VER sidecar (present)"; exit 0; fi
mkdir -p "$ROOT" "$BIN"
cd /tmp
rm -rf gccsidecar && mkdir gccsidecar && cd gccsidecar

pick() { # $1=pkg pattern -> latest matching amd64 deb
  curl -fsSL "$POOL/" | grep -oE "${1}_[^\"/_]*${PAT_REL}_amd64\.deb" | sort -V | tail -1
}
dl() { # $1=pkg $2=name-prefix
  f=$(pick "$1")
  [ -n "$f" ] || { echo "no deb matched: $1 ($PAT_REL)"; exit 1; }
  echo "== $f"
  curl -fsSLO "$POOL/$f"
  dpkg -x "$f" "$ROOT"
}

dl 'gcc-'"$VER_SFX"'-base' g_base
dl 'cpp-'"$VER_SFX" g_cpp
dl 'g\+\+-'"$VER_SFX" g_gxx
dl 'gcc-'"$VER_SFX" g_gcc
dl 'libgcc-'"$VER_SFX"'-dev' g_lgdev
dl 'libstdc\+\+-'"$VER_SFX"'-dev' g_lsdev

# era isl (cc1plus dependency) if the host lacks that soname
if [ -n "$ISL" ]; then
  islname=$(basename "$ISL")
  soname=$(echo "$islname" | grep -oE 'libisl[0-9]+')
  if ! ldconfig -p | grep -q "$soname"; then
    echo "== $islname (host lacks it)"
    curl -fsSLO "$ISL"
    dpkg -x "$islname" "$ROOT"
  fi
fi

# era mpfr (older cc1plus builds want libmpfr.so.4, modern hosts ship .so.6)
if ! ldconfig -p | grep -q 'libmpfr.so.4'; then
  f=$(curl -fsSL https://old-releases.ubuntu.com/ubuntu/pool/main/m/mpfr4/ | grep -oE 'libmpfr4_[^"]*_amd64\.deb' | sort -V | tail -1)
  echo "== $f (host lacks libmpfr.so.4)"
  curl -fsSLO "https://old-releases.ubuntu.com/ubuntu/pool/main/m/mpfr4/$f"
  dpkg -x "$f" "$ROOT"
fi

for tool in gcc g++; do
  binpath=$(find "$ROOT/usr/bin" -name "x86_64-linux-gnu-$tool-$VER_SFX" -o -name "$tool-$VER_SFX" 2>/dev/null | head -1)
  [ -n "$binpath" ] || { echo "no $tool-$VER_SFX binary in sidecar"; exit 1; }
cat > "$BIN/$tool" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH=$ROOT/usr/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH
exec $binpath "\$@"
EOF
chmod +x "$BIN/$tool"
done

"$BIN/g++" --version | head -1
echo 'int main(){return 0;}' > /tmp/ts.c
"$BIN/gcc" -c /tmp/ts.c -o /tmp/ts.o && echo GCC_CC1_OK
echo 'int main(){return 0;}' > /tmp/ts.cpp
"$BIN/g++" -c /tmp/ts.cpp -o /tmp/ts.o && echo GCC_CXX_OK
echo "GCC${VER}_SIDECAR_READY"
