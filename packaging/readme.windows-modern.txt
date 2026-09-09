BRP4 Binary Radio Pulsar Search - MODERN CUDA Build (single exe)
=================================================================
Port: "BRP4 CUDA port by Alperen Yavuz" (the signature is embedded in the
binary; visible on stderr / results header)
Version: v1.2-modern

What is this?
-------------
The MODERN package of the v1.2 BRP4 CUDA port: one plain executable, no
router. For NVIDIA GPUs from the
GTX 900 series (Maxwell) up to the RTX 50 series (Blackwell):
native SASS for sm_50/61/75/86/89/90 plus Blackwell family sections and
compute_50 PTX (future GPUs keep working through driver JIT).

  OLDER CARD? (GTX 400/500 Fermi, GTX 600/700 or GT 7xx Kepler)
  -> use the kepler (_cuda102_kepler) or fermi (_cuda80_fermi) package.
  MIXED RIG or UNSURE? -> use the router package (_router), it picks
  the right build automatically. Install only ONE package.

Contents of this package
------------------------
  einsteinbinary_BRP4_windows_x86_64_modern.exe   the application
  cufft64_11.dll                                       NVIDIA cuFFT (CUDA 12)
  app_info.xml                                         BOINC anonymous platform
  app_config.xml                                       BOINC project-folder settings

Requirements
------------
  - Windows 10/11 x64
  - NVIDIA GPU: GTX 900 series or newer (Maxwell sm_50 minimum)
  - NVIDIA driver r575 or newer (CUDA 12.9 era)

Installation (BOINC anonymous platform)
---------------------------------------
1) Open your BOINC project folder:
      C:\ProgramData\BOINC\projects\einstein.phys.uwm.edu\
2) Back up and DELETE any existing app_info.xml there.
3) Copy ALL files from this package into that folder.
4) Restart BOINC and make sure "Use GPU" is enabled in the client settings.
The declared version number is deliberately 99: project guidance asks custom
builds to stay below 100 so they never collide with official versions.

Standalone usage (no BOINC needed for testing)
----------------------------------------------
  einsteinbinary_BRP4_windows_x86_64_modern.exe ^
      -i input.binary -t bank.txt -l zaplist.txt ^
      -o results.dat -c checkpoint.dat -W -D 0 -z

Key flags: -i input time series, -t template bank, -l zap list,
-o candidate output, -c checkpoint file (delete it before a fresh run).
Run with --help for the complete list.

Known limitation (IMPORTANT!)
-----------------------------
The CURRENT Einstein@Home Ter5 "sband_dns" tasks belong to the new-generation
official application (BRP7, MeerKAT data), whose new options (--pb_min,
--start_template_id, ...) and source are not publicly released yet - even the
latest official public BRP4 cuda exe rejects those arguments. If you
advertise BRP4NVIDIA via app_info.xml such work may be sent to you and THIS
build CANNOT finish it ("unrecognized option --pb_min", exit 4).
Safe usage: standalone tests or classic "-t bank" style work.

Test status (honest)
--------------------
Same binary as the modern build inside the v1.2 full package:
RTX 5070 Ti (sm_120) full end-to-end run, exit 0; SASS/PTX coverage
verified with cuobjdump.

License
-------
The upstream Einstein@Home BRP4 source is GPL v2+; this build is distributed
under the same license.
