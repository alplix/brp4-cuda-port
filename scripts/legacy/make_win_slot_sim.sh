#!/usr/bin/env bash
# Simulates a real BOINC slot on Windows: ONLY the router + init_data.xml in
# the slot; era binaries/DLLs stay in the "project" dir (brp4-wintest).
set -euo pipefail
SLOT=/mnt/c/Users/Alp/brp4-winslot/slots/0
rm -rf /mnt/c/Users/Alp/brp4-winslot
mkdir -p "$SLOT"
cp /root/winrouter/einsteinbinary_BRP4_windows_x86_64_router.exe "$SLOT/"
cp /root/synth_kepler/synthetic.binary /root/synth_kepler/bank.txt /root/synth_kepler/zaplist.txt "$SLOT/"
printf '<project_dir>C:\\Users\\Alp\\brp4-wintest</project_dir>\n<gpu_device_num>-1</gpu_device_num>\n' > "$SLOT/init_data.xml"
cat "$SLOT/init_data.xml"
echo SLOT_READY
