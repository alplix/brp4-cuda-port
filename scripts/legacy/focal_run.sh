#!/usr/bin/env bash
# Run a command inside the focal build chroot (see setup_focal_chroot.sh).
# Bind-mounts /proc /dev /opt (CUDA toolkits) and the repository (at /repo).
set -euo pipefail
R=/root/focal
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
mkdir -p "$R/proc" "$R/dev" "$R/opt" "$R/repo" "$R/sys"
bind() { mountpoint -q "$2" || mount --bind "$1" "$2"; }
bind /proc "$R/proc"
bind /dev "$R/dev"
bind /opt "$R/opt"
bind "$REPO" "$R/repo"
cp -L /etc/resolv.conf "$R/etc/resolv.conf" 2>/dev/null || true
exec chroot "$R" env HOME=/root LANG=C.UTF-8 REPO=/repo \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"
