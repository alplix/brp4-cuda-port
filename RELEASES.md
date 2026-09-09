# Paste-ready release texts

Put all three archives in one release and paste section **A** into the
"Release notes" box, or open separate releases and use the per-archive
blurbs in section **B**.

---

## v1.2 — "every NVIDIA GPU" release (Kepler + Fermi era builds, router)

**BRP4 CUDA port v1.2 — now for EVERY NVIDIA GPU: Fermi (2010) → Blackwell**

Unofficial CUDA builds of the Einstein@Home BRP4 GPU app. v1.1 covered
Maxwell → Blackwell; v1.2 adds two legacy era builds and a tiny router that
picks the right binary for your GPU automatically:

- **fermi build** (CUDA 8.0, SASS sm_20, driver 390.x+): GTX 400/500 series,
  GT 610/620/630 (GF108/GF119), GT 430/440/530/540
- **kepler build** (CUDA 10.2, SASS sm_30/35/37, driver 470.x+): GTX 600/700
  series, GT 710/720/730/740, GTX Titan / Titan Black, K40/K80
- **modern build** (CUDA 12.9, SASS sm_50→120 + family, driver r575+):
  GTX 900/1000 → RTX 50 series — native code, no JIT

The router reads the compute capability from the driver (BOINC-assigned
device aware, `BRP4_BUILD` env override), so one package serves every card
and mixed-GPU rigs route correctly. Each era links its own cuFFT
(`cufft64_11/10/80.dll` on Windows, small `.so` files on Linux — names
don't collide). All builds by Alperen Yavuz; GPLv2+ like the upstream source.

Two flavours per platform — install ONE of them (both declare the same app):

| Asset | Contents |
|---|---|
| `einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.2.zip` | **FULL** — router + modern/kepler/fermi builds + 3 cuFFT DLLs + app_info/app_config + README |
| `einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.2.tar.gz` | **FULL** — router + modern/kepler/fermi builds + 2 era cuFFT libs + app_info/app_config + README |
| `einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.2_classic.zip` | **CLASSIC** — single modern-only exe (GTX 900+), no router, + `cufft64_11.dll` + app_info/app_config + README |
| `einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.2_classic.tar.gz` | **CLASSIC** — single modern-only exe (GTX 900+), no router, static cuFFT + app_info/app_config + README |
| `einsteinbinary_BRP4_linux_aarch64_cuda_custom_v1.1.tar.gz` | ARM64 — unchanged from v1.1 (Jetson TX1→Orin, ARM servers, DGX Spark) |

**Known limitation:** current Ter5 `sband_dns` tasks require unpublished
newer official app options (`--pb_min` etc.) — classic `-t bank` style work
and standalone runs are what these builds target.

**Test status:** all six era executables verified with cuobjdump (SASS
ladder + era PTX). RTX 5070 Ti: modern build end-to-end; kepler and fermi
builds exercised end-to-end through their compute_35/compute_20 PTX JIT
paths with identical candidate lists. Real Kepler/Fermi hardware
validation is pending community feedback — GT/GTX 6xx-7xx and GTX 4xx/5xx
owners, your reports are the missing piece.

---

## v1.1 (historical)

**BRP4 CUDA port — unofficial modernized Einstein@Home Binary Radio Pulsar Search**

Unofficial CUDA builds of the Einstein@Home BRP4 GPU app, rebuilt for CUDA
12.9-era drivers and current GPUs (native SASS for sm_50/61/75/86/89/90/120,
Blackwell family SASS sm_100f/sm_120f so future family members such as the
sm_121 in DGX Spark run native, plus compute PTX for whatever comes after).
Scientific code is unmodified upstream; the GPU plumbing was modernized and
the device modules are embedded fatbins. All builds by Alperen Yavuz, GPLv2+
like the upstream source.

What is new in v1.1:
- Linux binaries rebuilt on an Ubuntu 20.04 baseline — glibc floor drops from
  2.34 to 2.29 (Ubuntu 18.04+/Debian 10+ now work)
- Blackwell family-SASS added to every build (native execution on future
  family members such as sm_121 without waiting for a newer CUDA)
- ARM64 docs now also cover ARM workstations/servers with NVIDIA PCIe cards
  and DGX Spark, not only Jetson boards
- app_info.xml now declares a user-friendly app name

| Asset | Platform | Devices |
|---|---|---|
| `einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.0.zip` | Windows 10/11 x64 (+ `cufft64_11.dll`, app_info/app_config) | GTX 900 → RTX 50 series |
| `einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.1.tar.gz` | Linux x86_64, single file, cuFFT statically linked | GTX 900 → RTX 50 series |
| `einsteinbinary_BRP4_linux_aarch64_cuda_custom_v1.1.tar.gz` | Linux ARM64 / Jetson (sm_53–90 + Blackwell family + compute_53 PTX) | Jetson TX1→Orin, ARM servers with NVIDIA GPUs, DGX Spark |

Requirements: NVIDIA GPU with driver r575+. Each archive contains BOINC
`app_info.xml` / `app_config.xml` for anonymous-platform use.

**Known limitation:** current Ter5 `sband_dns` tasks require unpublished
newer official app options (`--pb_min` etc.) that these binaries do not
have — they target classic `-t bank` workloads / standalone runs.

Validated: RTX 5070 Ti end-to-end on Windows and Linux, arch coverage via
cuobjdump (SASS ladder + family sections), glibc floor verified via symbol
table (GLIBC_2.29), ARM64 startup under qemu-aarch64.

---

## v1.0 (historical)

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

### Per-archive blurbs (v1.0, historical)

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
