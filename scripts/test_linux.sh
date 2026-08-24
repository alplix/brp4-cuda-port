#!/usr/bin/env bash
set -e
REPO="/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port"
PROJ=/root/build/proj
mkdir -p "$PROJ/test"
ln -sfn /root/build/brp4-src "$PROJ/src"
cp "$REPO/test/make_synthetic.c" "$PROJ/test/"
EXE=/root/build/brp4-src/einsteinbinary_linux_x86_64_cuda_custom
RUN=/root/synth_run
mkdir -p $RUN && cd $RUN
rm -f results.dat results.dat.tmp checkpoint.dat boinc_finish_called stderr.old
echo "=== binary info ==="
ls -la $EXE
ldd $EXE || true
echo "=== building generator ==="
gcc -O2 -Wall -o make_synthetic "$PROJ/test/make_synthetic.c" -lm
./make_synthetic --outdir .
echo "=== running app ==="
set +e
$EXE -i synthetic.binary -t bank.txt -l zaplist.txt \
     -o results.dat -c checkpoint.dat -W -D 0 -z > app_stdout.log 2> stderr.txt
STATUS=$?
set -e
echo "app_exit=$STATUS"
tail -3 stderr.txt
if [ $STATUS -eq 0 ] && [ -s results.dat ]; then
  echo "=== top candidates ==="
  grep -v '^%' results.dat | head -5
fi
exit $STATUS
