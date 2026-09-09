BRP4 Binary Radio Pulsar Search - CLASSIC CUDA Build (single exe)
=================================================================
Port: "BRP4 CUDA port by Alperen Yavuz" (the signature is embedded in the
binary; visible on stderr / results header)
Version: v1.2-classic

What is this?
-------------
The CLASSIC variant of the v1.2 BRP4 CUDA port: one plain executable, no
router, exactly like the v1.0/v1.1 packages. For NVIDIA GPUs from the
GTX 900 series (Maxwell) up to the RTX 50 series (Blackwell):
native SASS for sm_50/61/75/86/89/90 plus Blackwell family sections and
compute_50 PTX (future GPUs keep working through driver JIT).

  GOT AN OLDER CARD? (GTX 400/500 Fermi, GTX 600/700 or GT 7xx Kepler)
  -> use the FULL package with the auto-picking router instead.
  Install only ONE of the two packages - they declare the same app.

Contents of this package
------------------------
  einsteinbinary_BRP4_linux_x86_64_cuda_custom   the application, single file
  app_info.xml                                   BOINC anonymous platform
  app_config.xml                                 BOINC project-folder settings

cuFFT is linked statically INTO the binary. The only runtime dependencies
are libcuda.so.1 (provided by the NVIDIA driver) and glibc >= 2.34.

Requirements
------------
  - Linux x86_64 with glibc >= 2.34 (Ubuntu 22.04+, Debian 12+, Fedora 36+ ...)
  - NVIDIA GPU: GTX 900 series or newer (Maxwell sm_50 minimum)
  - NVIDIA driver r575 or newer (CUDA 12.9 era)

Installation (BOINC anonymous platform)
---------------------------------------
1) Open your BOINC project folder:
      /var/lib/boinc-client/projects/einstein.phys.uwm.edu/
2) Back up and DELETE any existing app_info.xml there.
3) Copy ALL files from this package into that folder and make sure the
   binary is executable:
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
latest official public BRP4 cuda exe rejects those arguments. If you
advertise BRP4NVIDIA via app_info.xml such work may be sent to you and THIS
build CANNOT finish it ("unrecognized option --pb_min", exit 4).
Safe usage: standalone tests or classic "-t bank" style work.

Test status (honest)
--------------------
Same binary as the modern build inside the v1.2 full package:
RTX 5070 Ti (sm_120) full end-to-end run, exit 0; kill -9 checkpoint
restore verified on this code path in v1.0; SASS/PTX coverage verified
with cuobjdump.

License
-------
The upstream Einstein@Home BRP4 source is GPL v2+; this build is distributed
under the same license.
