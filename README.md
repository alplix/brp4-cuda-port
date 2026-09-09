# BRP4 CUDA port — Einstein@Home Binary Radio Pulsar Search, re-coded for every NVIDIA GPU

Unofficial CUDA builds of the [Einstein@Home](https://www.einsteinathome.org)
**Binary Radio Pulsar Search (BRP4)** GPU application — **completely re-coded**
so it runs **fast and flawlessly** on every NVIDIA generation from a Fermi-era
**GTX 560** gathering dust in an old office PC all the way up to an RTX 5090.

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

- **One package, every NVIDIA GPU since 2010.** Each platform ships a tiny
  **router** that reads the GPU's compute capability from the driver and
  starts the right era build automatically:

  | Build | Toolkit | Embedded GPU code | Cards | Driver floor |
  |---|---|---|---|---|
  | modern | CUDA 12.9 | SASS sm_50/61/75/86/89/90/100f/120f + PTX | GTX 900 → RTX 50 | r575 |
  | kepler | CUDA 10.2 | SASS sm_30/35/37 + PTX | GTX 600/700, GT 710–740, Titan | 470.x |
  | fermi | CUDA 8.0 | SASS sm_20 (+21 via sm_20) + PTX | GTX 400/500, GT 610/620/630 | 390.x |

  The x86_64 builds additionally embed **compute PTX** (lowest arch of their
  era) so any newer GPU JIT-compiles them — which is also how the legacy
  builds were functionally validated on a modern card.
- **BOINC-aware routing.** The router reads BOINC's `init_data.xml` for the
  assigned GPU device (and honours `--device`); `BRP4_BUILD=modern|kepler|fermi`
  overrides the choice. Note: one driver must support every GPU in the box —
  very old and very new cards cannot share a single driver.
- **Single-file Linux binaries.** The modern build links cuFFT statically.
  The kepler/fermi builds carry their era cuFFT as one small `.so` next to
  the binary (NVIDIA's static cuFFT from those toolkits needs a device-link
  pass that cannot be mixed with this app's driver-API design). The only
  other runtime dependency is `libcuda.so.1` from the driver itself.
- **Windows keeps the official-app convention**: the executable is
  accompanied by NVIDIA's cuFFT DLL of its era (`cufft64_11/10/80.dll` —
  the names don't collide, all three ship in one package).
- **BOINC-native.** Every archive ships its own `app_info.xml` +
  `app_config.xml` for anonymous-platform deployment, and the wrapper speaks
  the full BOINC lifecycle: initialization, checkpointing, suspend/resume,
  termination and crash reporting with a stack trace on stderr.
- **Bullet-proof checkpointing.** Progress is flushed to disk continuously;
  the application was verified to survive `kill -9` mid-run and resume with
  **bit-identical results**.
- **Reproducible builds.** The whole toolchain (dependencies, BOINC libs,
  CUDA components — including the era toolchains and the extracted gcc-8.3 /
  gcc-5.5 "sidecar" compilers their old front-ends require) is provisioned
  by idempotent scripts — see [Building from source](#building-from-source).

## Downloads & supported platforms (v1.2)

One package per GPU family — grab the one that matches your card, drop it in.
Not sure or running mixed GPUs? Take the router package, it auto-picks.
Install only ONE package (all declare the same app).

| Package | Cards | Notes |
|---|---|---|
| **Windows x64** `..._modern_v1.2.zip` | GTX 900 → RTX 50 | single modern exe (CUDA 12.9), `cufft64_11.dll` included |
| **Windows x64** `..._kepler_v1.2.zip` | GTX 600/700, GT 710–740, Titan | single kepler exe (CUDA 10.2), `cufft64_10.dll` included |
| **Windows x64** `..._fermi_v1.2.zip` | GTX 400/500, GT 610/620/630 | single fermi exe (CUDA 8.0), `cufft64_80.dll` included |
| **Windows x64** `..._router_v1.2.zip` | every NVIDIA GPU | router auto-picks among all three builds |
| **Linux x86_64** `..._modern_v1.2.tar.gz` | GTX 900 → RTX 50 | single modern exe, cuFFT static |
| **Linux x86_64** `..._kepler_v1.2.tar.gz` | GTX 600/700, GT 710–740, Titan | single kepler exe + `libcufft.so.10` |
| **Linux x86_64** `..._fermi_v1.2.tar.gz` | GTX 400/500, GT 610/620/630 | single fermi exe + `libcufft.so.8.0` |
| **Linux x86_64** `..._router_v1.2.tar.gz` | every NVIDIA GPU | router auto-picks among all three builds |
| **Linux ARM64** `_v1.1.tar.gz` | single aarch64 exe | Jetson TX1→Orin, ARM servers, DGX Spark |

Driver floors (set by NVIDIA's support lifecycle): modern build r575+,
kepler build 470.x (last Kepler branch), fermi build 390.x (last Fermi
branch). The archive names carry a `_vX.Y` suffix; the binaries inside keep
stable BOINC-facing names, and their embedded banner string reports the
exact build (`v1.2-kepler | BRP4 CUDA port by Alperen Yavuz`).

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
./einsteinbinary_BRP4_linux_x86_64_modern \
    -i input.binary -t bank.txt -l zaplist.txt \
    -o results.dat -c checkpoint.dat -W -D 0 -z
```

Key flags: `-i` input time series, `-t` template bank, `-l` zap list,
`-o` candidate output, `-c` checkpoint file (delete it before a fresh run).
Run with `--help` for the complete list. On Windows, keep the exe and
`cufft64_11.dll` in the same folder — the parameters are identical.

## Validation summary

- **All six era executables** (3 Linux + 3 Windows) verified with `cuobjdump`
  / `objdump`: SASS sm_20 · sm_30/35/37 · sm_50–120 (+family) respectively,
  plus era PTX embedded.
- **RTX 5070 Ti (sm_120):** modern build full end-to-end runs exit cleanly;
  the kepler and fermi builds were **functionally exercised end-to-end on
  the same card through their compute_35 / compute_20 PTX JIT paths**,
  producing identical candidate lists.
- Real Fermi/Kepler hardware runs are pending community field feedback.
- **Checkpoint/restore:** the modern build was killed with `SIGKILL` mid-run
  and resumed with output identical to an uninterrupted reference run.
- **Graceful shutdown:** on `SIGTERM` the work unit finishes safely and exits.
- **Router:** compute-capability routing (incl. BOINC `init_data.xml` device
  assignment and `BRP4_BUILD` override) tested on Linux and Windows.
- **Linux ARM64:** ELF/linkage verified, startup banner and `--help`
  exercised under qemu-aarch64; a real-GPU Jetson test is still pending
  hardware.

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

Windows targets cross-build too (fully from WSL — the era fatbins are
compiled by Linux nvcc, the host code by `x86_64-w64-mingw32-g++`, and the
cuFFT import libraries are generated from the era DLLs' export tables):

- `src/Makefile.win64.cuda` — parameterized for native MSYS2 builds and the
  WSL cross builds (see `scripts/legacy/build_win_era.sh`);
- `src/Makefile.win64.cuda.arm64` — llvm-mingw cross-build from WSL that
  reuses the x86_64 fatbins (device images are OS-agnostic) and generates
  its `nvcuda.dll`/`cufft64_11.dll` import libraries with `llvm-dlltool`
  from `.def` files in `src/win_arm64/`.

A synthetic end-to-end test lives in `test/make_synthetic.c` +
`test/run_cuda_test.sh`; checkpoint/restore is exercised by
`scripts/ckpt_test.sh` / `scripts/ckpt_kill9.sh`. The legacy-era
provisioning (CUDA 10.2 / CUDA 8.0 toolchains, the gcc-8.3 / gcc-5.5
sidecar compilers, import libs, packaging) is scripted in
`scripts/legacy/`.

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
