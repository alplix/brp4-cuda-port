#!/usr/bin/env bash
# Extracts the era cuFFT DLLs from the downloaded CUDA Windows installers
# (CUDA 10.2 -> kepler, CUDA 8.0 -> fermi), drops them into /root/wx/imports
# and builds COFF import libraries from their export tables.
set -euo pipefail
T=x86_64-w64-mingw32
DL=/root/dl_legacy
IMP=/root/wx/imports
mkdir -p "$IMP"

extract_one() { # $1=installer $2=workdir
  local exe="$DL/$1" dir="/root/wx/win_installers/$2"
  if [ ! -f "$exe" ]; then echo "== DEFER $1 (not downloaded)"; return 0; fi
  if [ -d "$dir" ] && find "$dir" -iname '*cufft64*.dll' | grep -q .; then
    echo "== SKIP extract $1 (already done)"; return 0; fi
  echo "== 7z-extracting $1 (this can take a while)"
  mkdir -p "$dir"
  7z x -y -o"$dir" "$exe" > "$dir/7z.log" 2>&1 || {
    echo "7z extraction had errors, checking for DLLs anyway"; tail -5 "$dir/7z.log"; }
  find "$dir" -iname '*cufft64*.dll' | head -5
}

extract_one cuda102_windows.exe cuda102
extract_one cuda80_windows.exe  cuda80

# import libs from whatever DLLs were found, keyed by their real names
emit_def() { # $1=dll $2=def-out
  # GNU objdump export-table lines look like:
  #   \t[   1] +base[   2]  0001 cufftCreate   -> name is the last field
  "$T-objdump" -p "$1" 2>/dev/null \
    | awk '/Ordinal\/Name Pointer.*Ordinal Base/{on=1;next} on && /^\t\[/{print $NF}' \
    > "$2.body"
  echo "EXPORTS" > "$2"
  cat "$2.body" >> "$2"
  rm -f "$2.body"
}

# nvcuda: use the real driver DLL from the Windows host (full export list)
if [ -f /mnt/c/Windows/System32/nvcuda.dll ]; then
  emit_def /mnt/c/Windows/System32/nvcuda.dll "$IMP/nvcuda.def"
  echo "nvcuda.dll: $(tail -n +2 "$IMP/nvcuda.def" | grep -c .) exports"
  "$T-dlltool" -d "$IMP/nvcuda.def" -D nvcuda.dll -l "$IMP/libnvcuda.a"
fi

for dll in $(find /root/wx/win_installers -iname '*cufft64*.dll' 2>/dev/null); do
  base=$(basename "$dll")
  cp "$dll" "$IMP/$base"
  emit_def "$IMP/$base" "$IMP/${base%.dll}.def"
  echo "$base: $(tail -n +2 "$IMP/${base%.dll}.def" | grep -c .) exports"
  "$T-dlltool" -d "$IMP/${base%.dll}.def" -D "$base" -l "$IMP/lib${base%.dll}.a"
done

ls -la "$IMP"
echo "ERA_DLL_IMPORTS_DONE"
