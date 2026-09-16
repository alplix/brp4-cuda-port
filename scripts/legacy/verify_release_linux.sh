#!/usr/bin/env bash
# Final release verification: extracts each of the 8 published archives
# fresh, then runs a complete synthetic work unit on the local GPU.
#   - modern  : native SASS path
#   - kepler  : compute_35 PTX JIT path
#   - fermi   : compute_20 PTX JIT path
#   - router  : auto-routing + the era binary it selects
# VERSION/DIST select which archives to verify (defaults: v1.3, /root/dist_v13).
set -uo pipefail
VERSION="${VERSION:-v1.3}"
D="${DIST:-/root/dist_${VERSION//./}}"
DATA="${DATA:-/root/synth_kepler}"
pass=0; fail=0

run_one() { # $1=dir $2=exe $3=tag
  local d="$1" exe="$2" tag="$3"
  cd "$d"
  rm -f results.dat checkpoint.dat
  "./$exe" -i synthetic.binary -t bank.txt -l zaplist.txt \
           -o results.dat -c checkpoint.dat -W -D 0 -z > run.log 2>&1
  local rc=$?
  local cand
  cand=$(awk "NF && !/^%/" results.dat 2>/dev/null | head -1)
  if [ $rc -eq 0 ] && [ -s results.dat ] && [ -n "$cand" ]; then
    echo "PASS $tag (rc=0): $cand"
    pass=$((pass+1))
  else
    echo "FAIL $tag (rc=$rc) - see $d/run.log"
    tail -5 run.log
    fail=$((fail+1))
  fi
}

echo "=========== LINUX ARCHIVES ($VERSION) ==========="
for pkg in modern kepler fermi router; do
  tgz=$(ls $D/einsteinbinary_BRP4_linux_x86_64_*${pkg}_${VERSION}.tar.gz 2>/dev/null | head -1)
  [ -z "$tgz" ] && { echo "FAIL archive missing for $pkg"; fail=$((fail+1)); continue; }
  d=/root/vfy_$pkg
  rm -rf "$d"; mkdir -p "$d"
  tar xzf "$tgz" -C "$d"
  cp $DATA/synthetic.binary $DATA/bank.txt $DATA/zaplist.txt "$d/"
  case $pkg in
    modern) exe=einsteinbinary_BRP4_linux_x86_64_modern;;
    kepler) exe=einsteinbinary_BRP4_linux_x86_64_kepler;;
    fermi)  exe=einsteinbinary_BRP4_linux_x86_64_fermi;;
    router) exe=einsteinbinary_BRP4_linux_x86_64_router;;
  esac
  run_one "$d" "$exe" "linux/$pkg"
done

echo "=========== SUMMARY ==========="
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ] && echo ALL_LINUX_GREEN
exit $fail
