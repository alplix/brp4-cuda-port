#!/usr/bin/env bash
# Assembles the v1.2 release packages. Eight x86_64 packages:
#   per-architecture single-exe packages (drop-in, no router):
#     modern (plain name) | kepler (_cuda102_kepler) | fermi (_cuda80_fermi)
#   plus the all-in-one router package (_router).
set -euo pipefail
REPO=/mnt/c/Users/Alp/.zcode/workspace/default/brp4-cuda-port
DIST=/root/dist_v12
T=x86_64-w64-mingw32
rm -rf "$DIST"
mkdir -p "$DIST"

LINUX_BIN=/root/pkgtest   # extracted from the current full tarball? no - use build outputs
MODERN_L=/root/build/modern_rebuild/einsteinbinary_linux_x86_64_cuda_custom
KEPLER_L=/root/build/era_kepler/einsteinbinary_BRP4_linux_x86_64_cuda102_kepler
FERMI_L=/root/build/era_fermi/einsteinbinary_BRP4_linux_x86_64_cuda80_fermi
ROUTER_L_SRC="$REPO/src/launcher/brp4_select.c"
MODERN_W=/root/build/wera_modern/einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe
KEPLER_W=/root/build/wera_kepler/einsteinbinary_BRP4_windows_x86_64_cuda102_kepler.exe
FERMI_W=/root/build/wera_fermi/einsteinbinary_BRP4_windows_x86_64_cuda80_fermi.exe
ROUTER_W=/root/winrouter/einsteinbinary_BRP4_windows_x86_64_router.exe
for f in "$MODERN_L" "$KEPLER_L" "$FERMI_L" "$MODERN_W" "$KEPLER_W" "$FERMI_W" "$ROUTER_W"; do
  [ -f "$f" ] || { echo "MISSING: $f"; exit 1; }
done

echo "===== [1/8] linux modern (plain name) ====="
L="$DIST/linux-modern"; mkdir -p "$L"
cp "$MODERN_L" "$L/einsteinbinary_BRP4_linux_x86_64_cuda_custom"
strip "$L/einsteinbinary_BRP4_linux_x86_64_cuda_custom" 2>/dev/null || true
chmod +x "$L/einsteinbinary_BRP4_linux_x86_64_cuda_custom"
cp "$REPO/packaging/app_info.linux-modern.xml" "$L/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$L/app_config.xml"
cp "$REPO/packaging/readme.linux-modern.txt" "$L/README.txt"
(cd "$L" && tar czf "$DIST/einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.2.tar.gz" ./*)

echo "===== [2/8] linux kepler ====="
L="$DIST/linux-kepler"; mkdir -p "$L"
cp "$KEPLER_L" "$L/einsteinbinary_BRP4_linux_x86_64_cuda102_kepler"
strip "$L/einsteinbinary_BRP4_linux_x86_64_cuda102_kepler" 2>/dev/null || true
chmod +x "$L/einsteinbinary_BRP4_linux_x86_64_cuda102_kepler"
cp /opt/cuda102/lib64/libcufft.so.10 "$L/"
strip "$L/libcufft.so.10" 2>/dev/null || true
cp "$REPO/packaging/app_info.linux-kepler.xml" "$L/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$L/app_config.xml"
cp "$REPO/packaging/readme.linux-kepler.txt" "$L/README.txt"
(cd "$L" && tar czf "$DIST/einsteinbinary_BRP4_linux_x86_64_cuda102_kepler_v1.2.tar.gz" ./*)

echo "===== [3/8] linux fermi ====="
L="$DIST/linux-fermi"; mkdir -p "$L"
cp "$FERMI_L" "$L/einsteinbinary_BRP4_linux_x86_64_cuda80_fermi"
strip "$L/einsteinbinary_BRP4_linux_x86_64_cuda80_fermi" 2>/dev/null || true
chmod +x "$L/einsteinbinary_BRP4_linux_x86_64_cuda80_fermi"
cp /opt/cuda80/lib64/libcufft.so.8.0 "$L/"
strip "$L/libcufft.so.8.0" 2>/dev/null || true
cp "$REPO/packaging/app_info.linux-fermi.xml" "$L/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$L/app_config.xml"
cp "$REPO/packaging/readme.linux-fermi.txt" "$L/README.txt"
(cd "$L" && tar czf "$DIST/einsteinbinary_BRP4_linux_x86_64_cuda80_fermi_v1.2.tar.gz" ./*)

echo "===== [4/8] linux router (all builds) ====="
L="$DIST/linux-router"; mkdir -p "$L"
gcc -O2 -Wall -o "$L/einsteinbinary_BRP4_linux_x86_64_router" "$ROUTER_L_SRC" -ldl
cp "$MODERN_L" "$L/einsteinbinary_BRP4_linux_x86_64_cuda_custom"
cp "$KEPLER_L" "$FERMI_L" "$L/"
cp /opt/cuda102/lib64/libcufft.so.10 /opt/cuda80/lib64/libcufft.so.8.0 "$L/"
strip "$L/libcufft.so.10" "$L/libcufft.so.8.0" 2>/dev/null || true
strip "$L"/einsteinbinary_BRP4_linux_x86_64_cuda102_kepler "$L"/einsteinbinary_BRP4_linux_x86_64_cuda80_fermi 2>/dev/null || true
chmod +x "$L"/einsteinbinary_*
cp "$REPO/packaging/app_info.linux.xml" "$L/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$L/app_config.xml"
cp "$REPO/packaging/readme.linux-router.txt" "$L/README.txt"
(cd "$L" && tar czf "$DIST/einsteinbinary_BRP4_linux_x86_64_cuda_custom_router_v1.2.tar.gz" ./*)

echo "===== [5/8] windows modern (plain name) ====="
W="$DIST/win-modern"; mkdir -p "$W"
cp "$MODERN_W" "$W/einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe"
cp /root/wx/imports/cufft64_11.dll "$W/"
cp "$REPO/packaging/app_info.windows-modern.xml" "$W/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$W/app_config.xml"
cp "$REPO/packaging/readme.windows-modern.txt" "$W/README.txt"
(cd "$W" && zip -q -r "$DIST/einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.2.zip" ./*)

echo "===== [6/8] windows kepler ====="
W="$DIST/win-kepler"; mkdir -p "$W"
cp "$KEPLER_W" "$W/einsteinbinary_BRP4_windows_x86_64_cuda102_kepler.exe"
cp /root/wx/imports/cufft64_10.dll "$W/"
cp "$REPO/packaging/app_info.windows-kepler.xml" "$W/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$W/app_config.xml"
cp "$REPO/packaging/readme.windows-kepler.txt" "$W/README.txt"
(cd "$W" && zip -q -r "$DIST/einsteinbinary_BRP4_windows_x86_64_cuda102_kepler_v1.2.zip" ./*)

echo "===== [7/8] windows fermi ====="
W="$DIST/win-fermi"; mkdir -p "$W"
cp "$FERMI_W" "$W/einsteinbinary_BRP4_windows_x86_64_cuda80_fermi.exe"
cp /root/wx/imports/cufft64_80.dll "$W/"
cp "$REPO/packaging/app_info.windows-fermi.xml" "$W/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$W/app_config.xml"
cp "$REPO/packaging/readme.windows-fermi.txt" "$W/README.txt"
(cd "$W" && zip -q -r "$DIST/einsteinbinary_BRP4_windows_x86_64_cuda80_fermi_v1.2.zip" ./*)

echo "===== [8/8] windows router (all builds) ====="
W="$DIST/win-router"; mkdir -p "$W"
cp "$ROUTER_W" "$W/einsteinbinary_BRP4_windows_x86_64_router.exe"
cp "$MODERN_W" "$KEPLER_W" "$FERMI_W" "$W/"
cp /root/wx/imports/cufft64_11.dll /root/wx/imports/cufft64_10.dll /root/wx/imports/cufft64_80.dll "$W/"
cp "$REPO/packaging/app_info.windows.xml" "$W/app_info.xml"
cp "$REPO/packaging/app_config.xml" "$W/app_config.xml"
cp "$REPO/packaging/readme.windows-router.txt" "$W/README.txt"
(cd "$W" && zip -q -r "$DIST/einsteinbinary_BRP4_windows_x86_64_cuda_custom_router_v1.2.zip" ./*)

echo "===== archives ====="
ls -la "$DIST"/*.tar.gz "$DIST"/*.zip
echo "PACKAGE_DONE"
