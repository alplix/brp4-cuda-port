BRP4 Binary Radio Pulsar Search - Custom CUDA Build for LINUX ARM64 (Jetson)
============================================================================
Port: "BRP4 CUDA port by Alperen Yavuz" (the signature is embedded in the
binary; visible on stderr / results header)
Version: v1.0

What is this?
-------------
A custom CUDA port of the Einstein@Home "Binary Radio Pulsar Search" (BRP4)
science application, re-coded for speed and smooth operation on modern GPUs,
built for 64-bit ARM Linux devices with an NVIDIA GPU. It runs through the
CUDA Driver API and carries multi-arch GPU code embedded inside the
executable itself - native SASS for sm_53, 62, 72, 87 and 90 plus
compute_53 PTX:

    sm_53  Jetson TX1 / Nano family
    sm_62  Jetson TX2
    sm_72  Jetson AGX Xavier / Xavier NX
    sm_87  Jetson AGX Orin / Orin NX / Orin Nano
    sm_90  Thor / Grace-class parts
    compute_53 PTX -> newer chips keep working via driver JIT

Note: this is pointless on ordinary ARM servers or Raspberry Pi boards -
they have no NVIDIA GPU and no CUDA.

Contents of this package
------------------------
  einsteinbinary_BRP4_linux_aarch64_cuda_custom   the application, single file (~290 MB)
  app_info.xml                                    BOINC anonymous-platform declaration
  app_config.xml                                  BOINC project-folder settings

cuFFT is linked statically INTO the binary. The only runtime dependencies are
libcuda.so.1 (provided by the NVIDIA driver / JetPack) and glibc >= 2.34.

Requirements
------------
  - Linux running on 64-bit ARM (aarch64) with a CUDA-capable NVIDIA GPU
  - NVIDIA driver r575 or newer (CUDA 12.9 era); on Jetson use the current
    JetPack driver stack
  - glibc >= 2.34 (Ubuntu 22.04+ base images are fine)

Installation (BOINC anonymous platform)
---------------------------------------
1) Open your BOINC project folder:
      /var/lib/boinc-client/projects/einstein.phys.uwm.edu/
   (path differs if you run BOINC as another user or use a sandbox)
2) Back up and DELETE any existing app_info.xml there.
3) Copy ALL files from this package (binary + both .xml files) into that
   folder and make sure the binary is executable:
      chmod +x einsteinbinary_BRP4_linux_aarch64_cuda_custom
4) Restart BOINC and make sure "Use GPU" is enabled in the client settings.
The declared version number is deliberately 99: project guidance asks custom
builds to stay below 100 so they never collide with official versions.

Standalone usage (no BOINC needed for testing)
----------------------------------------------
  ./einsteinbinary_BRP4_linux_aarch64_cuda_custom \
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

Status / validation summary
---------------------------
  - aarch64 ELF verified; dependencies only libcuda.so.1 + glibc
  - startup banner + --help exercised under qemu-aarch64 emulation
  - NOT yet tested on a real Jetson GPU (no hardware available) - if you run
    it on one, results feedback is very welcome!

License
-------
The upstream Einstein@Home BRP4 source is GPL v2+; this build is distributed
under the same license.
