# BRP4 CUDA port — Einstein@Home Binary Radio Pulsar Search, modernized

Unofficial CUDA ports of the [Einstein@Home](https://www.einsteinathome.org)
**Binary Radio Pulsar Search (BRP4)** GPU application, rebuilt for current
CUDA (12.x/13.x) and current GPUs up to **Blackwell (sm_120)**.

Port and builds by **Alperen Yavuz**, based on the GPL-licensed upstream
BRP4 source (`brp-src-release.zip` from Einstein@Home). The scientific code
is used unmodified; only the GPU plumbing was modernized:

- legacy texture references → module globals + `__ldg`
- deprecated `cuParamSet*`/`cuLaunchGrid*` → `cuLaunchKernel`
- `cuPrintf` removed; `cufftSetCompatibilityMode` removed
- driver-API host code, multi-arch **fatbin device modules embedded in the
  executable** and loaded via `cuModuleLoadData`
- cuFFT linked **statically on Linux** (single-file binary); Windows keeps
  NVIDIA's `cufft64_11.dll` like the official apps

## Downloads & supported platforms (v1.0)

| Platform | Package | Supported devices |
|---|---|---|
| **Windows 10/11 x64** | `einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.0.zip` | Any NVIDIA GPU from **GTX 900 series up to RTX 50 series** (Maxwell → Blackwell). `cufft64_11.dll` included |
| **Linux x86_64** | `einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.0.tar.gz` | Same GPUs as Windows; single-file binary (cuFFT linked statically) |
| **Linux ARM64** | `einsteinbinary_BRP4_linux_aarch64_cuda_custom_v1.0.tar.gz` | **NVIDIA Jetson** family — TX1/TX2 (sm_53/62), Xavier (sm_72), Orin (sm_87); newer SoCs via PTX JIT |

GPU coverage in detail:
- x86_64 builds embed native SASS for **sm_50, 61, 75, 86, 89, 90, 120** plus
  **compute_50 PTX**, so any current card runs at full speed and future ones
  keep working through driver JIT.
- ARM64 build embeds SASS for **sm_53, 62, 72, 87, 90** plus
  **compute_53 PTX**.
- NVIDIA driver **r575 or newer** required everywhere.

Each archive ships its own BOINC `app_info.xml` + `app_config.xml`.
Archive names carry a `_vX.Y` suffix; the binaries inside keep stable
BOINC-facing names, and their embedded banner string reports the exact
version (`v1.0 | BRP4 CUDA port by Alperen Yavuz`).

## Known limitation (important!)

The **current** Einstein@Home Ter5 `sband_dns` tasks belong to the
new-generation official application (**BRP7**, MeerKAT data), whose new
command-line options (`--pb_min`, `--start_template_id`, …) and source code
have not been published yet — even the latest official public CUDA exe of
BRP4 rejects them. These builds therefore target classic `-t bank` style
work / standalone runs and will **fail** on the newest Ter5 work if you
advertise them via `app_info.xml`. See `README.txt` inside each archive.

## Building from source

Everything builds inside WSL2 Ubuntu via helper scripts in [`scripts/`](scripts/)
(see [`scripts/README.md`](scripts/README.md) for the layout and gotchas):

```sh
scripts/wsl_setup.sh      # one-shot deps + BOINC libs + CUDA 12.9 redist
scripts/build_linux.sh    # Linux x86_64 build
scripts/finalize_linux.sh # strip + verify arch coverage
scripts/arm_env.sh && scripts/arm_deps.sh && scripts/arm_boinc.sh && scripts/arm_build.sh   # aarch64
```

Windows targets cross-build too:

- `src/Makefile.win64.cuda` — MSYS2 MinGW-w64 g++ + NVIDIA nvcc (native)
- `src/Makefile.win64.cuda.arm64` — llvm-mingw cross from WSL; reuses the
  x86_64 fatbins (device images are OS-agnostic), import libraries for
  `nvcuda.dll`/`cufft64_11.dll` are generated with `llvm-dlltool` from
  `.def` files in `src/win_arm64/`

A synthetic end-to-end test lives in `test/make_synthetic.c` +
`test/run_cuda_test.sh`; checkpoint/restore is exercised by
`scripts/ckpt_test.sh` / `scripts/ckpt_kill9.sh`.

## Validation summary

- RTX 5070 Ti (sm_120): full runs exit 0; Windows/Linux candidates bit-identical
- Checkpoint/restore after `kill -9`: resumes mid-run, output identical to reference
- Architecture coverage verified with `cuobjdump` (SASS sm_50…120 + compute_50 PTX)
- Linux ARM64 smoke-tested under qemu-aarch64 (banner + `--help`); real-GPU test pending Jetson hardware

## License

Upstream BRP4 source is GPLv2+; this port is distributed under the same
terms (see [LICENSE](LICENSE)). BOINC is LGPL and built separately;
NVIDIA CUDA/cuFFT are governed by their own EULAs and are not redistributed
here.
