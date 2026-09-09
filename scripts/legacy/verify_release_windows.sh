#!/usr/bin/env bash
# Final release verification on Windows: extracts each published zip fresh
# and runs a complete synthetic work unit on the local GPU.
set -u
DIST=/c/Users/Alp/dist
DATA=/c/Users/Alp/brp4-wintest
pass=0; fail=0

run_one() { # $1=dir $2=exe $3=tag
  local d="$1" exe="$2" tag="$3"
  cd "$d"
  rm -f results.dat checkpoint.dat
  ./"$exe" -i synthetic.binary -t bank.txt -l zaplist.txt \
           -o results.dat -c checkpoint.dat -W -D 0 -z > run.log 2>&1
  local rc=$?
  local cand
  cand=$(awk 'NF && !/^%/' results.dat 2>/dev/null | head -1)
  if [ $rc -eq 0 ] && [ -s results.dat ] && [ -n "$cand" ]; then
    echo "PASS $tag (rc=0): $cand"
    pass=$((pass+1))
  else
    echo "FAIL $tag (rc=$rc)"
    tail -5 run.log 2>/dev/null
    fail=$((fail+1))
  fi
}

for pkg in modern kepler fermi router; do
  zipf=$(ls $DIST/einsteinbinary_BRP4_windows_x86_64_*${pkg}_v1.2.zip 2>/dev/null | head -1)
  [ -z "$zipf" ] && { echo "FAIL archive missing for $pkg"; fail=$((fail+1)); continue; }
  d=/c/Users/Alp/vfy_win_$pkg
  rm -rf "$d"; mkdir -p "$d"
  unzip -o -q "$zipf" -d "$d"
  cp "$DATA/synthetic.binary" "$DATA/bank.txt" "$DATA/zaplist.txt" "$d/"
  case $pkg in
    modern) exe=einsteinbinary_BRP4_windows_x86_64_modern.exe;;
    kepler) exe=einsteinbinary_BRP4_windows_x86_64_kepler.exe;;
    fermi)  exe=einsteinbinary_BRP4_windows_x86_64_fermi.exe;;
    router) exe=einsteinbinary_BRP4_windows_x86_64_router.exe;;
  esac
  run_one "$d" "$exe" "windows/$pkg"
done

echo "=========== SUMMARY ==========="
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ] && echo ALL_WINDOWS_GREEN
exit $fail
