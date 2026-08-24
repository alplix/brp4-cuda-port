# Paste-ready release texts

Put all three archives in one release and paste section **A** into the
"Release notes" box, or open separate releases and use the per-archive
blurbs in section **B**.

---

## A) One release, all three archives

**BRP4 CUDA port — unofficial modernized Einstein@Home Binary Radio Pulsar Search**

Unofficial CUDA builds of the Einstein@Home BRP4 GPU app, rebuilt for CUDA
12.9-era drivers and current GPUs (native SASS for sm_50/61/75/86/89/90/120
plus compute_50 PTX for future cards). Scientific code is unmodified upstream;
the GPU plumbing was modernized and the device modules are embedded fatbins.
All builds by Alperen Yavuz, GPLv2+ like the upstream source.

| Asset | Platform | Devices |
|---|---|---|
| `einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.0.zip` | Windows 10/11 x64 (+ `cufft64_11.dll`, app_info/app_config) | GTX 900 → RTX 50 series |
| `einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.0.tar.gz` | Linux x86_64, single file, cuFFT statically linked | GTX 900 → RTX 50 series |
| `einsteinbinary_BRP4_linux_aarch64_cuda_custom_v1.0.tar.gz` | Linux ARM64 / Jetson (sm_53–90 + compute_53 PTX) | Jetson TX1/TX2/Xavier/Orin |

Requirements: NVIDIA GPU with driver r575+. Each archive contains BOINC
`app_info.xml` / `app_config.xml` for anonymous-platform use.

**Known limitation:** current Ter5 `sband_dns` tasks require unpublished
newer official app options (`--pb_min` etc.) that these binaries do not
have — they target classic `-t bank` workloads / standalone runs.

Validated: RTX 5070 Ti end-to-end (Windows/Linux bit-identical results),
kill -9 checkpoint/restore identical output, arch coverage via cuobjdump.

---

## B) Per-archive blurbs

### einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.0.zip (Windows x64)
CUDA port of the Einstein@Home BRP4 pulsar search for 64-bit Windows.
Embedded multi-arch fatbin (sm_50…120 SASS + compute_50 PTX), driver-API
only host code, cuFFT kept as NVIDIA's `cufft64_11.dll` (included).
Ships `app_info.xml` + `app_config.xml`. Driver r575+ required. GPL v2+.
Note: current Ter5 tasks need a newer non-public official app (`--pb_min`);
classic `-t bank` runs are supported.

### einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.0.tar.gz (Linux x86_64)
Single-file Linux build — cuFFT is linked statically, only runtime
dependencies are libcuda.so.1 and glibc. Same embedded sm_50…120 fatbin,
driver r575+. Includes `app_info.xml` + `app_config.xml`. GPL v2+.

### einsteinbinary_BRP4_linux_aarch64_cuda_custom_v1.0.tar.gz (Linux ARM64)
ARM64 build aimed at Jetson-class devices: native SASS for sm_53 (TX1-class
baseline), 62, 72 (Xavier), 87 (Orin), 90 plus compute_53 PTX for newer SoCs
via JIT. Single file, static cuFFT, needs only libcuda.so.1 + glibc >= 2.34.
Smoke-tested under qemu-aarch64; real-GPU validation pending hardware.
