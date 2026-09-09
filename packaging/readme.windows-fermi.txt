BRP4 Binary Radio Pulsar Search - FERMI CUDA Build for WINDOWS x64
==================================================================
Port: "BRP4 CUDA port by Alperen Yavuz" (the signature is embedded in the
binary; visible on stderr / results header)
Version: v1.2-fermi

This package is for NVIDIA FERMI GPUs (compute capability 2.x):
  GTX 400 / 500 series (GTX 460, 470, 480, 560, 570, 580, 590 ...),
  GT 430 / 440 / 450 / 520 / 530 / 540 / 550, GT 610 / 620 / 630 (GF108/GF119)
Built with CUDA 8.0: native SASS for sm_20 (sm_21 cards run it natively)
plus compute_20 PTX.

  GTX 900 or NEWER? -> use the modern package (plain name).
  MIXED RIG or UNSURE? -> use the router package (_router), it picks
  the right build automatically. Install only ONE package.

Contents of this package
------------------------
  einsteinbinary_BRP4_windows_x86_64_cuda80_fermi.exe   the application
  cufft64_80.dll                                        NVIDIA cuFFT (CUDA 8.0)
  app_info.xml / app_config.xml                         BOINC anonymous platform

Requirements: 64-bit Windows and the last Fermi driver branch (390/391.x).

Installation (BOINC anonymous platform)
---------------------------------------
1) Open C:\ProgramData\BOINC\projects\einstein.phys.uwm.edu\
2) Back up and DELETE any existing app_info.xml there.
3) Copy ALL files from this package into that folder.
4) Restart BOINC, "Use GPU" enabled.
Version number 99 by design: custom builds stay below the official 100.

Standalone usage
----------------
  einsteinbinary_BRP4_windows_x86_64_cuda80_fermi.exe ^
      -i input.binary -t bank.txt -l zaplist.txt ^
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
on an RTX 5070 Ti through the compute_20 PTX JIT path with correct
candidates. Real Fermi hardware: pending community feedback - GTX 560
owners, your report is the missing datapoint.

License: upstream BRP4 source is GPL v2+; this build is distributed under
the same license.
