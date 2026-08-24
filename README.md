# BRP4 CUDA port — Einstein@Home Binary Radio Pulsar Search, re-coded for modern GPUs

Unofficial CUDA builds of the [Einstein@Home](https://www.einsteinathome.org)
**Binary Radio Pulsar Search (BRP4)** GPU application — **completely re-coded**
so it runs **fast and flawlessly** on today's hardware, from a GTX 950 gathering
dust in an old office PC all the way up to an RTX 5090.

Port and builds by **Alperen Yavuz**, based on the GPL-licensed upstream BRP4
source (`brp-src-release.zip`, published by Einstein@Home).

---

## Why a rewrite?

The original public BRP4 CUDA application was written in the CUDA 3.x era.
Its GPU layer leans on interfaces that NVIDIA has since deprecated or removed
entirely, so the stock source no longer builds cleanly against any current
CUDA toolkit, and even where it compiles it leaves performance on the table.
This project replaces that entire layer with a clean, modern implementation:

| Old (upstream) | New (this port) |
|---|---|
| Legacy texture references for device lookups | Module globals read through `__ldg` (read-only data cache) |
| Deprecated `cuParamSet*` + `cuLaunchGrid*` launch path | Single `cuLaunchKernel` calls with parameter buffers |
| `cuPrintf` debug scaffolding baked into kernels | Removed entirely — zero overhead |
| `cufftSetCompatibilityMode` (API removed in cuFFT ≥ 6) | Dropped; FFT plan setup simplified |
| Device code shipped as loose cubin files next to the exe | Multi-arch **fatbins embedded inside the executable**, loaded at runtime via `cuModuleLoadData` |
| Host code written against ancient driver versions | Tested end-to-end against current drivers (r575+) |

The scientific pipeline (demodulation, harmonic summing, candidate ranking)
is the battle-tested upstream code — the plumbing around it is brand new.

## Technical highlights

- **One binary, every NVIDIA GPU.** Each x86_64 build embeds native SASS for
  **sm_50, 61, 75, 86, 89, 90 and 120** (Maxwell → Blackwell) plus
  **compute_50 PTX**, so GPUs released *after* this port still work through
  the driver's JIT compiler. The ARM64 build embeds SASS for
  **sm_53, 62, 72, 87, 90** plus **compute_53 PTX**.
- **Single-file Linux binaries.** On Linux, cuFFT is linked statically —
  the only runtime dependencies are `libcuda.so.1` and glibc. Copy one file,
  run it. On Windows the official-app convention is kept: the executable is
  accompanied by NVIDIA's `cufft64_11.dll`.
- **BOINC-native.** Every archive ships its own `app_info.xml` +
  `app_config.xml` for anonymous-platform deployment, and the wrapper speaks
  the full BOINC lifecycle: initialization, checkpointing, suspend/resume,
  termination and crash reporting with a stack trace on stderr.
- **Bullet-proof checkpointing.** Progress is flushed to disk continuously;
  the application was verified to survive `kill -9` mid-run and resume with
  **bit-identical results**.
- **Reproducible builds.** The whole toolchain (dependencies, BOINC libs,
  CUDA components, cross-compilers) is provisioned by idempotent scripts —
  see [Building from source](#building-from-source).

## Downloads & supported platforms (v1.0)

| Platform | Package | Supported devices |
|---|---|---|
| **Windows 10/11 x64** | `einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.0.zip` | Any NVIDIA GPU from the **GTX 900 series up to the RTX 50 series** (Maxwell → Blackwell); `cufft64_11.dll` included |
| **Linux x86_64** | `einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.0.tar.gz` | Same GPU range as Windows; single-file binary (statically linked cuFFT) |
| **Linux ARM64** | `einsteinbinary_BRP4_linux_aarch64_cuda_custom_v1.0.tar.gz` | **NVIDIA Jetson** family — TX1/TX2 (sm_53/62), Xavier (sm_72), Orin (sm_87); newer SoCs via PTX JIT |

Requirements everywhere: an NVIDIA GPU and driver **r575 or newer**.

Archive names carry a `_vX.Y` suffix; the binaries inside keep stable
BOINC-facing names, and their embedded banner string reports the exact
version (`v1.0 | BRP4 CUDA port by Alperen Yavuz`) — so you always know
which build produced a result.

## Installation (BOINC anonymous platform)

1. Open your BOINC project folder:
   - Windows: `C:\ProgramData\BOINC\projects\einstein.phys.uwm.edu\`
   - Linux: `/var/lib/boinc-client/projects/einstein.phys.uwm.edu/`
2. Back up and then **delete** any existing `app_info.xml` there.
3. Copy this package's `app_info.xml`, `app_config.xml` and the binaries
   (on Windows also `cufft64_11.dll`) into that folder.
4. Restart BOINC and make sure *Activity → Use GPU* is enabled.

The declared version number is deliberately **99**: project guidance asks
custom builds to stay below 100 so they never collide with official versions.

## Standalone usage

No BOINC needed for testing:

```sh
./einsteinbinary_BRP4_linux_x86_64_cuda_custom \
    -i input.binary -t bank.txt -l zaplist.txt \
    -o results.dat -c checkpoint.dat -W -D 0 -z
```

Key flags: `-i` input time series, `-t` template bank, `-l` zap list,
`-o` candidate output, `-c` checkpoint file (delete it before a fresh run).
Run with `--help` for the complete list. On Windows, keep the exe and
`cufft64_11.dll` in the same folder — the parameters are identical.

## Validation summary

- **RTX 5070 Ti (sm_120):** full end-to-end runs exit cleanly; Windows and
  Linux builds produce **bit-identical** candidate lists.
- **Checkpoint/restore:** the process was killed with `SIGKILL` mid-run and
  resumed afterwards — final output identical to an uninterrupted reference run.
- **Graceful shutdown:** on `SIGTERM` the work unit finishes safely and exits.
- **Architecture coverage:** verified with `cuobjdump`
  (SASS sm_50…120 + compute_50 PTX embedded as claimed).
- **Linux ARM64:** ELF/linkage verified, startup banner and `--help` exercised
  under qemu-aarch64; a real-GPU Jetson test is still pending hardware.

## Known limitation (important!)

The **current** Einstein@Home Ter5 `sband_dns` tasks belong to the
new-generation official application (**BRP7**, MeerKAT data), whose new
command-line options (`--pb_min`, `--start_template_id`, …) and source code
have not been published yet — even the latest official public CUDA exe of
BRP4 rejects them. These builds therefore target classic `-t bank` style
work / standalone runs and will **fail** on the newest Ter5 work if you
advertise them via `app_info.xml`. See `README.txt` inside each archive.

## Building from source

Everything builds inside WSL2 Ubuntu via helper scripts in
[`scripts/`](scripts/) — see [`scripts/README.md`](scripts/README.md) for
the exact layout and known pitfalls:

```sh
scripts/wsl_setup.sh       # one-shot deps + BOINC libs + CUDA 12.9 redist
scripts/build_linux.sh     # Linux x86_64 build
scripts/finalize_linux.sh  # strip + verify architecture coverage
scripts/arm_env.sh && scripts/arm_deps.sh && scripts/arm_boinc.sh && \
scripts/arm_build.sh       # aarch64 cross build
```

Windows targets cross-build too:

- `src/Makefile.win64.cuda` — MSYS2 MinGW-w64 g++ + NVIDIA nvcc (native);
- `src/Makefile.win64.cuda.arm64` — llvm-mingw cross-build from WSL that
  reuses the x86_64 fatbins (device images are OS-agnostic) and generates
  its `nvcuda.dll`/`cufft64_11.dll` import libraries with `llvm-dlltool`
  from `.def` files in `src/win_arm64/`.

A synthetic end-to-end test lives in `test/make_synthetic.c` +
`test/run_cuda_test.sh`; checkpoint/restore is exercised by
`scripts/ckpt_test.sh` / `scripts/ckpt_kill9.sh`.

### Repository layout

| Path | Contents |
|---|---|
| `src/` | Ported application sources and all makefiles (Linux CUDA, ARM64 CUDA, Windows CUDA, Windows-on-ARM cross) |
| `src/compat/` | Portability shims added by the port |
| `src/win_arm64/` | Symbol definitions used to generate PE import libraries |
| `scripts/` | Reproducible WSL2 environment, build, packaging and stress-test scripts |
| `test/` | Synthetic signal generator and end-to-end runner |
| `patches/` | Minimal patches applied to third-party dependencies during scripted builds |

(The heavy third-party trees are intentionally not checked in — the scripts
download and patch them reproducibly.)

## License

Upstream BRP4 source is GPLv2+; this port is distributed under the same
terms (see [LICENSE](LICENSE)). BOINC is LGPL and built separately; NVIDIA
CUDA/cuFFT are governed by their own EULAs and are not redistributed here.
