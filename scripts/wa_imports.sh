#!/usr/bin/env bash
# Extract imported symbol names from the x86 Windows exe import tables
# and emit .def files for building ARM64 COFF import libraries.
set -e
EXE=/mnt/c/Users/Alp/dist/einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe
OBJDUMP=/opt/llvm-mingw/bin/llvm-objdump
OUT=/root/wa

"$OBJDUMP" -p "$EXE" > /tmp/imports.txt

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

for dll, fname in [('cufft64_11.dll', '/root/wa/cufft64_11.def'),
                   ('nvcuda.dll', '/root/wa/nvcuda.def')]:
    syms = sections.get(dll, [])
    with open(fname, 'w') as f:
        f.write('LIBRARY %s\nEXPORTS\n' % dll)
        for s in sorted(set(syms)):
            f.write(s + '\n')
    print(dll, len(syms), 'imports ->', fname)
EOF
