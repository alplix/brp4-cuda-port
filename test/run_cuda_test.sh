#!/bin/bash
# End-to-end standalone test of a BRP4 CUDA build (no BOINC client needed).
#
#   1. builds the synthetic input generator (gcc)
#   2. generates a small time series + template bank + zaplist
#   3. runs the executable on them (-z = debug, -W = whitening/zapping) so the
#      whole pipeline gets exercised: CUDA context, embedded fatbin module
#      loading, resampling kernels, cuFFT, harmonic summing, candidate output.
#
# Expected result: exit code 0, "Data processing finished successfully!" and
# top candidates clustered around the injected frequency (default 100 Hz).
#
# Usage: bash run_cuda_test.sh <path-to-exe> [make_synthetic options]
#   e.g. bash test/run_cuda_test.sh dist/einsteinbinary_BRP4_windows_x86_64_modern.exe
#        bash test/run_cuda_test.sh ./einsteinbinary_BRP4_linux_x86_64_modern --samples 4194304 --templates 64 --amp 0.02
# On Windows the matching cufft64_*.dll must sit next to the exe.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
EXE="${1:?usage: run_cuda_test.sh <path-to-exe> [make_synthetic options]}"
shift
RUN_DIR="$HERE/out"

mkdir -p "$RUN_DIR"
echo "=== building generator ==="
gcc -O2 -Wall -o "$RUN_DIR/make_synthetic" "$HERE/make_synthetic.c" -lm

cd "$RUN_DIR"
rm -f results.dat results.dat.tmp checkpoint.dat boinc_finish_called stderr.old
./make_synthetic "$@" --outdir .

echo "=== running app ==="
set +e
"$EXE" -i synthetic.binary -t bank.txt -l zaplist.txt \
       -o results.dat -c checkpoint.dat -W -D 0 -z
STATUS=$?
set -e
echo "app_exit=$STATUS"

if [ $STATUS -eq 0 ] && [ -s results.dat ]; then
  echo "=== top candidates ==="
  grep -v '^%' results.dat | sed '/^$/d' | head -5
fi
exit $STATUS
