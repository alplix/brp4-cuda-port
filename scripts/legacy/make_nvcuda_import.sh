#!/usr/bin/env bash
# Builds COFF import libraries for the Windows x86_64 cross builds:
#   libnvcuda.a        - from the import table of the released v1.0 exe
#   libcufft64_*.dll.a - from the export tables of the era cufft DLLs
set -euo pipefail
T=x86_64-w64-mingw32
OUT=/root/wx/imports
REPO=/mnt/c/Users/Alp/.zcode/workspace/default/brp4-cuda-port
ZIP=/mnt/c/Users/Alp/AppData/Local/Temp/brp4_v11_inspect/einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.0.zip
mkdir -p "$OUT" /root/wx/v10exe

if [ ! -f /root/wx/v10exe/einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe ]; then
  cd /root/wx/v10exe
  unzip -o -q "$ZIP"
fi
EXE=/root/wx/v10exe/einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe
[ -f "$EXE" ] || EXE=$(ls /root/wx/v10exe/*.exe | head -1)
echo "== using $EXE"

"$T-objdump" -p "$EXE" > /tmp/imports.txt
python3 - <<'EOF'
import re
sections = {}
cur = None
for line in open('/tmp/imports.txt'):
    m = re.match(r'\s*DLL Name: (\S+)', line)
    if m:
        cur = m.group(1)
        sections[cur] = []
        continue
    if cur:
        m = re.match(r'\s*\d+\s+(\S+)\s*$', line)
        if m:
            sections[cur].append(m.group(1))
for dll, fname in [('cufft64_11.dll', '/root/wx/imports/cufft64_11.def'),
                   ('nvcuda.dll', '/root/wx/imports/nvcuda.def')]:
    syms = sections.get(dll, [])
    with open(fname, 'w') as f:
        f.write('LIBRARY %s\nEXPORTS\n' % dll)
        for s in sorted(set(syms)):
            f.write(s + '\n')
    print(dll, len(syms), 'imports ->', fname)
EOF

"$T-dlltool" -d /root/wx/imports/nvcuda.def -D nvcuda.dll -l "$OUT/libnvcuda.a"
echo "== libnvcuda.a done"
ls -la "$OUT"
echo "NVCUDA_IMPORT_READY"
