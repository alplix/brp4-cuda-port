#!/usr/bin/env bash
# Assembles the v1.2 release packages (Linux tar.gz + Windows zip).
set -euo pipefail
REPO=/mnt/c/Users/Alp/.zcode/workspace/default/brp4-cuda-port
DIST=/root/dist_v12
T=x86_64-w64-mingw32
rm -rf "$DIST"
mkdir -p "$DIST/linux" "$DIST/win"

echo "===== staging Linux package ====="
L="$DIST/linux"
# modern build (built with default makefile target name, rename to release name)
cp /root/build/modern_rebuild/einsteinbinary_linux_x86_64_cuda_custom "$L/einsteinbinary_BRP4_linux_x86_64_cuda_custom"
cp /root/build/era_kepler/einsteinbinary_BRP4_linux_x86_64_cuda102_kepler "$L/"
cp /root/build/era_fermi/einsteinbinary_BRP4_linux_x86_64_cuda80_fermi "$L/"
# router (built from src/launcher/brp4_select.c)
gcc -O2 -Wall -o "$L/einsteinbinary_BRP4_linux_x86_64_router" "$REPO/src/launcher/brp4_select.c" -ldl
# era cuFFT libraries (stripped)
cp /opt/cuda102/lib64/libcufft.so.10 "$L/"
cp /opt/cuda80/lib64/libcufft.so.8.0 "$L/"
strip "$L/libcufft.so.10" "$L/libcufft.so.8.0" 2>/dev/null || true
strip "$L"/einsteinbinary_BRP4_linux_x86_64_cuda102_kepler "$L"/einsteinbinary_BRP4_linux_x86_64_cuda80_fermi 2>/dev/null || true
chmod +x "$L"/einsteinbinary_*
cp "$REPO/packaging/app_info.linux.xml" "$L/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$L/app_config.xml"
cp "$REPO/packaging/readme.linux-x64.txt" "$L/README.txt"
ls -la "$L"

echo "===== staging Windows package ====="
W="$DIST/win"
cp /root/winrouter/einsteinbinary_BRP4_windows_x86_64_router.exe "$W/"
cp /root/build/wera_modern/einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe "$W/"
cp /root/build/wera_kepler/einsteinbinary_BRP4_windows_x86_64_cuda102_kepler.exe "$W/"
cp /root/build/wera_fermi/einsteinbinary_BRP4_windows_x86_64_cuda80_fermi.exe "$W/"
cp /root/wx/imports/cufft64_11.dll /root/wx/imports/cufft64_10.dll /root/wx/imports/cufft64_80.dll "$W/"
cp "$REPO/packaging/app_info.windows.xml" "$W/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$W/app_config.xml"
cp "$REPO/packaging/readme.windows-x64.txt" "$W/README.txt"
ls -la "$W"

echo "===== arch verification (modern win exe) ====="
"$T-objdump" -p "$W/einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe" | grep "DLL Name" | sort -u

echo "===== creating archives ====="
cd "$DIST/linux" && tar czf "$DIST/einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.2.tar.gz" ./*
cd "$DIST/win" && zip -q -r "$DIST/einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.2.zip" ./*

echo "===== staging CLASSIC packages (single modern exe, no router) ====="
LC="$DIST/linux-classic"
mkdir -p "$LC"
cp /root/build/modern_rebuild/einsteinbinary_linux_x86_64_cuda_custom "$LC/einsteinbinary_BRP4_linux_x86_64_cuda_custom"
strip "$LC/einsteinbinary_BRP4_linux_x86_64_cuda_custom" 2>/dev/null || true
chmod +x "$LC/einsteinbinary_BRP4_linux_x86_64_cuda_custom"
cp "$REPO/packaging/app_info.linux-classic.xml" "$LC/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$LC/app_config.xml"
cp "$REPO/packaging/readme.linux-classic.txt" "$LC/README.txt"
cd "$LC" && tar czf "$DIST/einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.2_classic.tar.gz" ./*

WC="$DIST/win-classic"
mkdir -p "$WC"
cp /root/build/wera_modern/einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe "$WC/"
cp /root/wx/imports/cufft64_11.dll "$WC/"
cp "$REPO/packaging/app_info.windows-classic.xml" "$WC/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$WC/app_config.xml"
cp "$REPO/packaging/readme.windows-classic.txt" "$WC/README.txt"
cd "$WC" && zip -q -r "$DIST/einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.2_classic.zip" ./*

ls -la "$DIST"/*.tar.gz "$DIST"/*.zip
echo "PACKAGE_DONE"
