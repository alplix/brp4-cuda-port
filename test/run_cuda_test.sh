#!/bin/bash
# End-to-end standalone test of the custom Windows CUDA BRP4 build.
#
#   1. builds the synthetic input generator (mingw gcc)
#   2. generates a small time series + template bank + zaplist
#   3. runs einsteinbinary_win_x86_64_cuda_custom.exe on them (-z = debug,
#      -W = whitening/zapping) so the whole pipeline gets exercised:
#      CUDA context, embedded-PTX module loading, resampling kernels,
#      cuFFT, harmonic summing and text candidate output.
#
# Expected result: exit code 0, "Data processing finished successfully!",
# top candidates clustered around the injected frequency (default 100 Hz).
#
# Usage: bash run_cuda_test.sh [path-to-exe]
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
EXE="${1:-/c/Users/Alp/dist/einsteinbinary_win_x86_64_cuda_custom.exe}"
RUN_DIR=/c/Users/Alp/AppData/Local/Temp/opencode/synthetic_run

mkdir -p "$RUN_DIR"
echo "=== building generator ==="
gcc -O2 -Wall -o "$RUN_DIR/make_synthetic.exe" "$HERE/make_synthetic.c"

cd "$RUN_DIR"
rm -f results.dat results.dat.tmp checkpoint.dat boinc_finish_called stderr.old
./make_synthetic.exe --outdir .

echo "=== running app ==="
set +e
"$EXE" -i synthetic.binary -t bank.txt -l zaplist.txt \
       -o results.dat -c checkpoint.dat -W -D 0 -z
STATUS=$?
set -e
echo "app_exit=$STATUS"

if [ $STATUS -eq 0 ] && [ -s results.dat ]; then
  echo "=== top candidates ==="
  grep -v '^%' results.dat | head -5
fi
exit $STATUS
