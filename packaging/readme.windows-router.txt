BRP4 Binary Radio Pulsar Search - CUDA Build for WINDOWS x64
===================================================================
Port: "BRP4 CUDA port by Alperen Yavuz" (the signature is embedded in every
binary; visible on stderr / results header)
Version: v1.2 - the "every NVIDIA GPU" release

What is this?
-------------
A custom CUDA port of the Einstein@Home "Binary Radio Pulsar Search" (BRP4)
science application, re-coded for speed and smooth operation across every
NVIDIA GPU generation from Fermi (2010) to Blackwell - not just modern cards.
It runs through the CUDA Driver API and carries multi-arch GPU code embedded
inside each executable.

This package contains THREE era builds plus a router:

  einsteinbinary_BRP4_windows_x86_64_router.exe         start-me program -
                                                        picks the right build
                                                        for your GPU
  einsteinbinary_BRP4_windows_x86_64_modern.exe    modern build (CUDA 12.9)
  einsteinbinary_BRP4_windows_x86_64_kepler.exe kepler build (CUDA 10.2)
  einsteinbinary_BRP4_windows_x86_64_fermi.exe   fermi build  (CUDA 8.0)
  cufft64_11.dll / cufft64_10.dll / cufft64_80.dll      era cuFFT libraries
  app_info.xml / app_config.xml                         BOINC anonymous platform

Which build runs on my GPU?
---------------------------
The router reads the compute capability from the NVIDIA driver and starts
the matching binary automatically:

  CC 2.x (Fermi)          -> fermi build   GTX 400/500 series, GT 610/620/630
                                           (GF108/GF119), GT 430/440/530/540
  CC 3.x (Kepler)         -> kepler build  GTX 650/660/670/680/690,
                                           GTX 760/770, GT 710/720/730/740,
                                           GTX Titan / Titan Black, K40/K80
  CC 5.x - 12.x           -> modern build  GTX 900/1000, RTX 20/30/40/50
                                           (Maxwell -> Blackwell)

On a mixed-GPU system the router follows the same device choice as the
application itself (BOINC's assigned GPU, else the most capable one).
You can force a specific build by setting the BRP4_BUILD system environment
variable (modern|kepler|fermi).

Requirements per build (driver!)
--------------------------------
  modern  : driver r575+ (Maxwell sm_50 minimum)
  kepler  : driver 470/474.x (last Kepler branch)
  fermi   : driver 390/391.x (last Fermi branch)

Everything else is linked statically; each era binary loads its own cuFFT
DLL (all three ship in this package, the DLL names do not collide).
Windows 7/8/10/11: use the driver branch matching your GPU generation.

Installation (BOINC anonymous platform)
---------------------------------------
1) Open your BOINC project folder:
      C:\ProgramData\BOINC\projects\einstein.phys.uwm.edu\
2) Back up and DELETE any existing app_info.xml there.
3) Copy ALL files from this package into that folder.
4) Restart BOINC and make sure "Use GPU" is enabled in the client settings.
The declared version number is deliberately 99: project guidance asks custom
builds to stay below 100 so they never collide with official versions.
app_info.xml points BOINC at the router - the router does the rest.

Standalone usage (no BOINC needed for testing)
----------------------------------------------
  einsteinbinary_BRP4_windows_x86_64_router.exe ^
      -i input.binary -t bank.txt -l zaplist.txt ^
      -o results.dat -c checkpoint.dat -W -D 0 -z
(run an era binary directly instead if you do not want auto-routing)

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
  - All three builds verified with cuobjdump: SASS sm_20 / sm_30+35+37 /
    sm_50..120 respectively, plus era PTX embedded
  - RTX 5070 Ti (sm_120): modern build end-to-end, exit 0
  - kepler and fermi builds were functionally exercised end-to-end on the
    RTX 5070 Ti through their compute_35 / compute_20 PTX JIT paths:
    identical candidate lists as the modern build on the same input
  - REAL Kepler/Fermi hardware runs are pending community feedback -
    GT/GTX 6xx-7xx and GTX 4xx/5xx owners: your reports are the missing
    piece, please post them in the forum thread

License
-------
The upstream Einstein@Home BRP4 source is GPL v2+; this build is distributed
under the same license.
