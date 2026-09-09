#!/usr/bin/env bash
# Downloads legacy CUDA toolchains needed for the Kepler/Fermi builds.
# Run inside WSL as root. Resumable: skips files already present.
set -u
cd /root/dl_legacy || exit 1

dl() {
  url="$1"; out="$2"
  if [ -f "$out" ]; then echo "== SKIP $out (exists)"; return 0; fi
  echo "== GET $out"
  curl -fSL --retry 3 --retry-delay 5 -C - -o "$out.part" "$url" || return 1
  mv "$out.part" "$out"
  echo "== OK  $out"
}

dl "https://developer.download.nvidia.com/compute/cuda/10.2/Prod/local_installers/cuda_10.2.89_440.33.01_linux.run" cuda102_linux.run
dl "https://developer.download.nvidia.com/compute/cuda/8.0/Prod2/local_installers/cuda_8.0.61_375.26_linux.run" cuda80_linux.run
dl "https://developer.download.nvidia.com/compute/cuda/10.2/Prod/local_installers/cuda_10.2.89_441.22_windows.exe" cuda102_windows.exe
dl "https://developer.download.nvidia.com/compute/cuda/8.0/Prod2/local_installers/cuda_8.0.61_2_windows.exe" cuda80_windows.exe
echo "ALL_DOWNLOADS_DONE"
