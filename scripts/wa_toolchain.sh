#!/usr/bin/env bash
set -e
# latest llvm-mingw release
API=https://api.github.com/repos/mstorsjo/llvm-mingw/releases/latest
URL=$(curl -fsSL $API | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['tag_name'])
for a in d['assets']:
    n=a['name']
    if 'ucrt-ubuntu' in n and 'x86_64' in n and n.endswith('.tar.xz'):
        print(a['browser_download_url']); break")
TAG=$(echo "$URL" | head -1)
DL=$(echo "$URL" | tail -1)
echo "llvm-mingw $TAG"
mkdir -p /opt/llvm-mingw && cd /opt/llvm-mingw
F=$(basename "$DL")
if [ ! -s "$F" ]; then curl -fsSL "$DL" -o "$F"; fi
tar xf "$F" --strip-components=1 -C /opt/llvm-mingw
ls /opt/llvm-mingw/bin/ | grep -E 'aarch64.*(g\+\+|gcc)$'
/opt/llvm-mingw/bin/aarch64-w64-mingw32-g++ --version | head -1
