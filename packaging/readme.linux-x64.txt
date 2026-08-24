BRP4 Binary Radio Pulsar Search - Custom CUDA Build for LINUX x86_64
====================================================================
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
  einsteinbinary_BRP4_linux_x86_64_cuda_custom   the application, single file (~295 MB)
  app_info.xml                                   BOINC anonymous-platform declaration
  app_config.xml                                 BOINC project-folder settings

cuFFT is linked statically INTO the binary. The only runtime dependencies are
libcuda.so.1 (provided by the NVIDIA driver) and glibc >= 2.34 - nothing else
to install.

Requirements
------------
  - Linux x86_64 with glibc >= 2.34 (Ubuntu 22.04+, Debian 12+, Fedora 36+ ...)
  - NVIDIA GPU (GTX 900 series or newer recommended; Maxwell sm_50 minimum)
  - NVIDIA driver r575 or newer (CUDA 12.9 era)

Installation (BOINC anonymous platform)
---------------------------------------
1) Open your BOINC project folder:
      /var/lib/boinc-client/projects/einstein.phys.uwm.edu/
   (path differs if you run BOICC as another user or use a sandbox)
2) Back up and DELETE any existing app_info.xml there.
3) Copy ALL files from this package (binary + both .xml files) into that
   folder and make sure the binary is executable:
      chmod +x einsteinbinary_BRP4_linux_x86_64_cuda_custom
4) Restart BOINC and make sure "Use GPU" is enabled in the client settings.
The declared version number is deliberately 99: project guidance asks custom
builds to stay below 100 so they never collide with official versions.

Standalone usage (no BOINC needed for testing)
----------------------------------------------
  ./einsteinbinary_BRP4_linux_x86_64_cuda_custom \
      -i input.binary -t bank.txt -l zaplist.txt \
      -o results.dat -c checkpoint.dat -W -D 0 -z

Key flags: -i input time series, -t template bank, -l zap list,
-o candidate output, -c checkpoint file (delete it before a fresh run).
Run with --help for the complete list.

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
    with the Windows build of the same version
  - Checkpoint/restore: killed with kill -9 mid-run, resumed, final output
    identical to an uninterrupted reference run
  - SIGTERM: finishes the work unit safely and exits
  - Architecture coverage verified with cuobjdump (sm_50..120 + compute_50 PTX)

License
-------
The upstream Einstein@Home BRP4 source is GPL v2+; this build is distributed
under the same license.
