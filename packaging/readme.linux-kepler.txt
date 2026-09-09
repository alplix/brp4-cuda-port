BRP4 Binary Radio Pulsar Search - KEPLER CUDA Build for LINUX x86_64
====================================================================
Port: "BRP4 CUDA port by Alperen Yavuz" (the signature is embedded in the
binary; visible on stderr / results header)
Version: v1.2-kepler

This package is for NVIDIA KEPLER GPUs (compute capability 3.x):
  GTX 650 / 650 Ti / 660 / 670 / 680 / 690, GTX 760 / 770,
  GT 710 / 720 / 730 / 740, GT 630 (GK208) / GT 640,
  GTX Titan, GTX 780 / 780 Ti, Titan Black, Quadro K40 / K80
Built with CUDA 10.2: native SASS for sm_30 / sm_35 / sm_37 plus
compute_35 PTX.

  GTX 900 or NEWER? -> use the modern package (plain name).
  MIXED RIG or UNSURE? -> use the router package (_router), it picks
  the right build automatically. Install only ONE package.

Contents of this package
------------------------
  einsteinbinary_BRP4_linux_x86_64_cuda102_kepler   the application
  libcufft.so.10                                    NVIDIA cuFFT (CUDA 10.2)
  app_info.xml / app_config.xml                     BOINC anonymous platform

Requirements: 64-bit Linux and the last Kepler driver branch (470.x).
Keep libcufft.so.10 next to the binary - it is found automatically.

Installation (BOINC anonymous platform)
---------------------------------------
1) Open /var/lib/boinc-client/projects/einstein.phys.uwm.edu/
2) Back up and DELETE any existing app_info.xml there.
3) Copy ALL files from this package into that folder and make sure the
   program is executable:
      chmod +x einsteinbinary_BRP4_linux_x86_64_cuda102_kepler
4) Restart BOINC, "Use GPU" enabled.
Version number 99 by design: custom builds stay below the official 100.

Standalone usage
----------------
  ./einsteinbinary_BRP4_linux_x86_64_cuda102_kepler \
      -i input.binary -t bank.txt -l zaplist.txt \
      -o results.dat -c checkpoint.dat -W -D 0 -z

Known limitation (IMPORTANT!)
-----------------------------
Current Ter5 "sband_dns" tasks belong to the newer BRP7 application whose
options (--pb_min, ...) and source are not public yet - even the latest
official public BRP4 exe rejects them. Safe usage: standalone tests or
classic "-t bank" style work.

Test status (honest)
--------------------
SASS/PTX coverage verified with cuobjdump; full end-to-end run exercised
on an RTX 5070 Ti through the compute_35 PTX JIT path with correct
candidates. Real Kepler hardware: pending community feedback - GT 730 /
GTX 660 owners, your report is the missing datapoint.

License: upstream BRP4 source is GPL v2+; this build is distributed under
the same license.
