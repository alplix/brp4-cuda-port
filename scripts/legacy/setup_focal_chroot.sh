#!/usr/bin/env bash
# Ubuntu 20.04 (glibc 2.31) build chroot for every Linux binary we ship.
#
# Why: the host-side objects and static libraries decide which glibc symbol
# versions end up in the executable (sqrtf@2.43, fmod/strlcpy/strlcat/
# __isoc23_*@2.38 ...). Building on a current distro silently raises the
# minimum glibc of the release (v1.3 shipped needing glibc 2.43 and could not
# start on Ubuntu 22.04). Building inside focal pins the floor at 2.31.
# The CUDA toolkits under /opt are shared with the host via bind mounts, only
# the host compiler / libc / static libs come from the chroot.
#
#   setup_focal_chroot.sh            create + provision /root/focal (idempotent)
#   focal_run.sh <cmd...>            run a command inside it (mounts handled)
set -euo pipefail
R=/root/focal
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

if [ ! -x "$R/bin/bash" ]; then
  echo "===== debootstrap focal ====="
  debootstrap --variant=minbase focal "$R" http://archive.ubuntu.com/ubuntu
fi

cat > "$R/etc/apt/sources.list" <<'EOF'
deb [arch=amd64] http://archive.ubuntu.com/ubuntu focal main universe
deb [arch=amd64] http://archive.ubuntu.com/ubuntu focal-updates main universe
deb [arch=amd64] http://security.ubuntu.com/ubuntu focal-security main universe
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal main universe
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal-updates main universe
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal-security main universe
EOF

bash "$REPO/scripts/legacy/focal_run.sh" bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture arm64
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential autoconf automake libtool pkg-config git curl ca-certificates \
  python3 xz-utils file binutils make \
  libgsl-dev libfftw3-dev libxml2-dev zlib1g-dev libssl-dev liblzma-dev \
  libzstd-dev binutils-dev libiberty-dev >/dev/null
# staged on purpose: one combined native+arm64 apt transaction fails with
# "held broken packages" on focal, the same packages install fine in sequence
apt-get install -y -qq --no-install-recommends crossbuild-essential-arm64 >/dev/null
for p in libxml2-dev zlib1g-dev liblzma-dev libzstd-dev libssl-dev libfftw3-dev; do
  apt-get install -y -qq --no-install-recommends "$p:arm64" >/dev/null
done
# libgsl-dev cannot be co-installed for both architectures on focal (it would
# replace the amd64 copy): unpack the arm64 debs by hand instead
mkdir -p /tmp/gslarm && cd /tmp/gslarm && rm -rf ./*.deb ./x
apt-get download libgsl-dev:arm64 libgsl23:arm64 libgslcblas0:arm64 >/dev/null 2>&1
for d in *.deb; do dpkg -x "$d" ./x; done
cp -a x/usr/lib/aarch64-linux-gnu/. /usr/lib/aarch64-linux-gnu/
echo "--- toolchain inside chroot:"
g++ --version | head -1
aarch64-linux-gnu-g++ --version | head -1
ldd --version | head -1
'
echo "FOCAL_CHROOT_READY"
