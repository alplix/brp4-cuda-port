#!/usr/bin/env bash
for V in 12.9.1 13.0.0 13.0.1; do
  J=https://developer.download.nvidia.com/compute/cuda/redist/redistrib_${V}.json
  echo "=== $V ==="
  curl -fsSL $J | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
except Exception as e:
    print('fetch failed', e); raise SystemExit
keys=[k for k in d if 'windows' in k]
print('windows keys:', keys)
for k in ['cuda_nvcc','cuda_cudart','libcufft']:
    c=d.get(k,{})
    w=[x for x in c if 'arm' in x or 'aarch' in x]
    print(k, '->', list(c.keys()), 'ARM:' , w)
"
done
