#!/bin/bash
set -e
PROJ="/c/ProgramData/BOINC/projects/einstein.phys.uwm.edu"
RUN=/c/Users/Alp/AppData/Local/Temp/opencode/ter5_official
mkdir -p "$RUN" && cd "$RUN"
cp "$PROJ/Ter5_3_sband_dns_cfbf00001_segment_8_dms_40_8.binary" .
cp "$PROJ/Ter5_3_sband_dns_cfbf00001_segment_8_dms_40.zap" .
cp "$PROJ/einsteinbinary_BRP4_windows_x86_64__cuda1291.exe" ./official.exe
cp "$PROJ/cufft64_11.dll" .
set +e
./official.exe \
  -i Ter5_3_sband_dns_cfbf00001_segment_8_dms_40_8.binary \
  -l Ter5_3_sband_dns_cfbf00001_segment_8_dms_40.zap \
  -o results.cand0 -c test.cpt \
  -A 0.04 -P 1.5 -f 500.0 -W \
  --pb_min 3600 --mc_max 1.6 --mp_min 1.1 --mismatch 0.222 --tobs 1800 --alpha 1.0 \
  --start_template_id 2350000 --no_of_templates 50000 -D 0 -z
echo "app_exit=$?"
set -e
echo "=== banner ==="
grep -iE "revision|version|Binary Pulsar|bank" stderr.txt | head -6
echo "=== tail ==="
tail -4 stderr.txt
ls -la results.cand0* 2>/dev/null || true
