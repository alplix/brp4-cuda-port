#!/usr/bin/env bash
cp /root/build/brp4-src/einsteinbinary_linux_x86_64_cuda_custom \
   /root/build/legacy118/einsteinbinary_linux_x86_64_cuda118_legacy /mnt/c/Users/Alp/dist/
cd /mnt/c/Users/Alp/dist
for f in einsteinbinary_win_x86_64_cuda_custom.exe \
         einsteinbinary_win_x86_64_cuda118_legacy.exe \
         einsteinbinary_linux_x86_64_cuda_custom \
         einsteinbinary_linux_x86_64_cuda118_legacy; do
  n=$(strings -a "$f" | grep -c 'Alperen Yavuz')
  echo "$f: $n"
done
