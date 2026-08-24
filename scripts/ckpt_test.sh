#!/usr/bin/env bash
set -e
EXE=/root/build/brp4-src/einsteinbinary_linux_x86_64_cuda_custom
PROJ=/root/build/proj
RUN=/root/ckpt_run
rm -rf $RUN && mkdir -p $RUN && cd $RUN
cp "/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port/test/make_synthetic.c" "$PROJ/test/make_synthetic.c"
gcc -O2 -Wall -o make_synthetic "$PROJ/test/make_synthetic.c" -lm
./make_synthetic --samples 131072 --templates 500000 --outdir .
ARGS="-i synthetic.binary -t bank.txt -l zaplist.txt -o results.dat -c checkpoint.dat -W -D 0 -z"

echo "=== PASS1: reference full run ==="
T0=$(date +%s)
$EXE $ARGS > out1.log 2> err1.txt || { echo "PASS1 FAILED"; tail -n 3 err1.txt; tail -n 3 out1.log; exit 1; }
T1=$(date +%s)
echo "ref_time=$((T1-T0))s"
cp results.dat results_ref.dat

echo "=== PASS2: interrupt mid-run ==="
rm -f results.dat checkpoint.dat boinc_finish_called
$EXE $ARGS > out2.log 2> err2.txt &
PID=$!
CKPT_SEEN=""
for i in $(seq 1 400); do
  sleep 2
  if [ -s checkpoint.dat ]; then CKPT_SEEN=yes; break; fi
  if ! kill -0 $PID 2>/dev/null; then break; fi
done
if [ -n "$CKPT_SEEN" ]; then echo "checkpoint seen after ~$((i*2))s"; else echo "NO CHECKPOINT"; fi
kill -TERM $PID 2>/dev/null && KILLED=yes || KILLED=already-exited
wait $PID; ST=$?
echo "killed=$KILLED pass2_exit=$ST"
ls -la checkpoint.dat results.dat 2>/dev/null || true

echo "=== PASS3: resume ==="
T2=$(date +%s)
set +e
$EXE $ARGS > out3.log 2> err3.txt
ST3=$?
set -e
T3=$(date +%s)
echo "resume_exit=$ST3 resume_time=$((T3-T2))s (ref $((T1-T0))s)"
if [ $ST3 -ne 0 ]; then tail -n 4 err3.txt; tail -n 4 out3.log; exit 1; fi
diff <(grep -v '^%' results.dat) <(grep -v '^%' results_ref.dat) > /dev/null \
  && echo "CANDIDATES IDENTICAL OK" \
  || { echo "DIFF!"; diff <(grep -v '^%' results.dat) <(grep -v '^%' results_ref.dat) | head -8; exit 1; }
