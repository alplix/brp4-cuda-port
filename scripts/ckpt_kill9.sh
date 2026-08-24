#!/usr/bin/env bash
set -e
EXE=/root/build/brp4-src/einsteinbinary_linux_x86_64_cuda_custom
RUN=/root/ckpt_run2
cd $RUN
ARGS="-i synthetic.binary -t bank.txt -l zaplist.txt -o results3.dat -c checkpoint3.dat -W -D 0 -z"
rm -f results3.dat checkpoint3.dat
$EXE $ARGS > outE.log 2> errE.txt &
PID=$!
for i in $(seq 1 400); do
  sleep 2
  [ -s checkpoint3.dat ] && break
  kill -0 $PID 2>/dev/null || break
done
echo "cpt detected ~$((i*2))s -> KILL -9"
od -A d -t d4 -j 4 -N 8 checkpoint3.dat | head -1
kill -9 $PID
wait $PID || true
echo "files: $(ls checkpoint3.dat results3.dat 2>/dev/null | tr '\n' ' ')"

echo "=== RESUME ==="
T1=$(date +%s)
$EXE $ARGS > outF.log 2> errF.txt
RC=$?
T2=$(date +%s)
echo "resume_exit=$RC resume_time=$((T2-T1))s"
diff <(grep -v '^%' results3.dat) <(grep -v '^%' ref.dat) > /dev/null \
  && echo "RESUME OUTPUT IDENTICAL TO REFERENCE OK" \
  || { echo DIFF; diff <(grep -v '^%' results3.dat) <(grep -v '^%' ref.dat) | head; exit 1; }
