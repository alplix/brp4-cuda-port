#!/usr/bin/env bash
# Builds the cufft import libraries for the era DLLs found in /root/wx/imports
set -euo pipefail
T=x86_64-w64-mingw32
IMP=/root/wx/imports
cd "$IMP"
# the modern DLL comes from the v1.0 release zip (extracted by
# make_nvcuda_import.sh); era DLLs come from extract_cufft_windows.sh
if [ -f /mnt/c/Users/Alp/AppData/Local/Temp/brp4_v11_inspect/win10zip/cufft64_11.dll ] && [ ! -f cufft64_11.dll ]; then
  cp /mnt/c/Users/Alp/AppData/Local/Temp/brp4_v11_inspect/win10zip/cufft64_11.dll .
fi
for dll in cufft64_11.dll cufft64_10.dll cufft64_80.dll; do
  [ -f "$dll" ] || { echo "== no $dll yet"; continue; }
  "$T-objdump" -p "$dll" 2>/dev/null \
    | awk '/Ordinal\/Name Pointer.*Ordinal Base/{on=1;next} on && /^\t\[/{print $NF}' > body.tmp
  { echo "EXPORTS"; cat body.tmp; } > "${dll%.dll}.def"
  rm body.tmp
  echo "$dll: $(tail -n +2 "${dll%.dll}.def" | grep -c .) exports"
  grep -E 'cufftPlan1d|cufftExecR2C|cufftDestroy' "${dll%.dll}.def" || echo "  (key exports missing!)"
  "$T-dlltool" -d "${dll%.dll}.def" -D "$dll" -l "lib${dll%.dll}.a"
done
ls -la "$IMP"/*.a
echo CUFFT_IMPORTS_DONE
