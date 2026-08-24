BRP4 Binary Radio Pulsar Search - Custom CUDA Build for WINDOWS x64
===================================================================
Port: "BRP4 CUDA port by Alperen Yavuz" (the signature is embedded in the
binary; visible on stderr / results header)
Version: v1.0

What is this?
-------------
A custom CUDA port of the Einstein@Home "Binary Radio Pulsar Search" (BRP4)
science application, re-coded for speed and smooth operation on modern GPUs.
It runs through the CUDA Driver API and carries multi-arch GPU code embedded
inside the executable itself - native SASS for sm_50, 61, 75, 86, 89, 90 and
120 (GTX 900 series up to RTX 50 series) plus compute_50 PTX so future GPUs
keep working through driver JIT.

Contents of this package
------------------------
  einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe   the application (~11 MB)
  cufft64_11.dll                                       REQUIRED - keep in the SAME folder as the exe
  app_info.xml                                         BOINC anonymous-platform declaration
  app_config.xml                                       BOINC project-folder settings

Requirements
------------
  - Windows 10 or 11, 64-bit x86
  - NVIDIA GPU (GTX 900 series or newer recommended; Maxwell sm_50 minimum)
  - NVIDIA driver r575 or newer (CUDA 12.9 era)

Installation (BOINC anonymous platform)
---------------------------------------
1) Open your BOINC project folder:
      C:\ProgramData\BOINC\projects\einstein.phys.uwm.edu\
2) Back up and DELETE any existing app_info.xml there.
3) Copy ALL files from this package (exe, cufft64_11.dll, app_info.xml,
   app_config.xml) INTO THAT FOLDER.
4) Restart BOINC and make sure Activity -> Use GPU is enabled.
The declared version number is deliberately 99: project guidance asks custom
builds to stay below 100 so they never collide with official versions.

Standalone usage (no BOINC needed for testing)
----------------------------------------------
Open a command prompt IN THIS FOLDER and run:

  einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe ^
      -i input.binary -t bank.txt -l zaplist.txt ^
      -o results.dat -c checkpoint.dat -W -D 0 -z

Key flags: -i input time series, -t template bank, -l zap list,
-o candidate output, -c checkpoint file (delete it before a fresh run).
Run with --help for the complete list.
IMPORTANT: cufft64_11.dll must sit next to the exe, otherwise the program
will not start.

Known limitation (IMPORTANT!)
-----------------------------
The CURRENT Einstein@Home Ter5 "sband_dns" tasks belong to the new-generation
official application (BRP7, MeerKAT data), whose new options (--pb_min,
--start_template_id, ...) and source are not publicly released yet - even the
latest official public BRP4 cuda1291.exe rejects those arguments. If you
advertise BRP4NVIDIA via app_info.xml such work may be sent to you and THIS
build CANNOT finish it ("unrecognized option --pb_min", exit 4).
Safe usage: standalone tests or classic "-t bank" style work.

Validation summary
------------------
  - RTX 5070 Ti (sm_120): full end-to-end run exit=0; candidates bit-identical
    with the Linux build of the same version
  - SIGTERM: finishes the work unit safely and exits
  - Architecture coverage verified with cuobjdump (sm_50..120 + compute_50 PTX)

License
-------
The upstream Einstein@Home BRP4 source is GPL v2+; this build is distributed
under the same license.
