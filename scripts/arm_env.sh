#!/usr/bin/env bash
set -e
. /etc/os-release
COD=${VERSION_CODENAME:-resolute}
dpkg --add-architecture arm64
# constrain main sources to amd64, add ports for arm64
SRC=/etc/apt/sources.list.d/ubuntu.sources
if [ -f "$SRC" ] && ! grep -q '^Architectures:' "$SRC"; then
  sed -i 's/^Types: deb$/Types: deb\nArchitectures: amd64/' "$SRC"
fi
cat > /etc/apt/sources.list.d/arm64-ports.sources <<EOF
Types: deb
URIs: https://ports.ubuntu.com/
Suites: $COD $COD-updates
Components: main universe
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-user qemu-user-binfmt >/dev/null
echo "--- binfmt entries:"
ls /proc/sys/fs/binfmt_misc/ | grep -i aarch || echo "NO AARCH64 ENTRY (need reboot or manual register)"
