#!/usr/bin/env bash
set -e
EXE=/root/build/brp4-src/einsteinbinary_linux_x86_64_cuda_custom
echo "=== stripping ==="
ls -la $EXE | awk '{print "before:", $5}'
strip $EXE
ls -la $EXE | awk '{print "after: ", $5}'
echo "=== quick re-test of stripped binary ==="
cd /root/synth_run
rm -f results.dat checkpoint.dat
$EXE -i synthetic.binary -t bank.txt -l zaplist.txt -o results.dat -c checkpoint.dat -W -D 0 > /dev/null 2>&1
echo "app_exit=$?"
grep -v '^%' results.dat | head -3
echo "=== installing cuobjdump ==="
mkdir -p /root/dl && cd /root/dl
if [ ! -f red129.json ]; then curl -fsSL -o red129.json https://developer.download.nvidia.com/compute/cuda/redist/redistrib_12.9.1.json; fi
if [ ! -x /opt/cuda129/bin/cuobjdump ]; then
  rel=$(python3 -c "import json;d=json.load(open('/root/dl/red129.json'));print(d['cuda_cuobjdump']['linux-x86_64']['relative_path'])")
  curl -fsSLO "https://developer.download.nvidia.com/compute/cuda/redist/$rel"
  tar -xf "$(basename $rel)" -C /opt/cuda129 --strip-components=1
fi
echo "=== embedded architectures ==="
/opt/cuda129/bin/cuobjdump --list-elf $EXE | grep -oE 'sm_[0-9]+' | sort | uniq -c
/opt/cuda129/bin/cuobjdump --list-ptx $EXE | grep -oE 'compute_[0-9]+' | sort | uniq -c
