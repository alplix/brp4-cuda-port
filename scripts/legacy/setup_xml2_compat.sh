#!/usr/bin/env bash
# Drops a libxml2.so.2 (Ubuntu jammy build) into /root/xml2compat so the
# ancient CUDA 10.2/8.0 installer binaries can run on a modern WSL.
set -euo pipefail
cd /root
mkdir -p /root/xml2compat
need_extract=0
if [ ! -f /root/xml2compat/usr/lib/x86_64-linux-gnu/libxml2.so.2 ]; then
  cd /root/xml2compat
  echo "== fetching jammy libxml2 deb"
  VER=libxml2_2.9.13+dfsg-1build1_amd64.deb
  echo "== picked $VER"
  curl -fsSLO "https://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/$VER"
  dpkg-deb -x "$VER" /root/xml2compat
  need_extract=1
fi
if [ ! -f /root/xml2compat/usr/lib/x86_64-linux-gnu/libicuuc.so.70 ]; then
  cd /root/xml2compat
  echo "== fetching jammy libicu70 deb"
  VER=libicu70_70.1-2_amd64.deb
  echo "== picked $VER"
  curl -fsSLO "https://archive.ubuntu.com/ubuntu/pool/main/i/icu/$VER"
  dpkg-deb -x "$VER" /root/xml2compat
fi
ls /root/xml2compat/usr/lib/x86_64-linux-gnu/ | grep -E '\.so' | head
echo "XML2_COMPAT_READY"
