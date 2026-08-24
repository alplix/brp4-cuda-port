# Build & Test Scripts (WSL2 Ubuntu, root)

All scripts are meant to run inside WSL: `wsl -d Ubuntu -u root -- bash /path/to/script.sh`
Keep them in the repo; copy to `/mnt/c/Users/Alp/AppData/Local/Temp/opencode/` (or run
directly from this folder via /mnt/c) — but NEVER put mutable state in WSL `/tmp`
(it is wiped when the VM idle-shuts-down; use `/root`).

## Layout inside WSL
| Path | Purpose |
|---|---|
| `/root/build/brp4-src` | build tree (makefile + sources synced from repo by build_linux.sh) |
| `/root/build/brp4-install` | BOINC 7.17 headers/libs (`include/boinc`, `lib`) |
| `/root/build/3rdparty/boinc-current_brp_apps` | BOINC source (needs `./_autosetup && ./configure --disable-server --disable-client --disable-manager --disable-apps --disable-unit-tests` once for config.h) |
| `/opt/cuda129` | CUDA 12.9 redist merge (nvcc/cudart/libcufft-static), layout uses `lib/` |
| `/opt/cuda129-arm64/root` | CUDA 12.9 **linux-aarch64** redist (headers + aarch64 nvcc run via binfmt) |
| `/opt/llvm-mingw` | llvm-mingw toolchain (aarch64-w64-mingw32 host builds) |
| `/root/wa/{deps,imports,brp4-install-arm64}` | Windows-ARM64 deps, generated import libs, BOINC libs |
| `/root/build/armwinbuild`, `/root/build/arm64build` | ARM64 build dirs (win / linux) |
| `/opt/cuda118` | CUDA 11.8 redist (legacy builds only) |
| `/root/synth_run`, `/root/ckpt_run*` | test scratch dirs |

## Scripts
- `wsl_setup.sh` — one-shot: apt deps, BOINC libs build/install, cuda129 download+extract
- `build_linux.sh` — sync makefile/compat/version-headers from repo → brp4-src, then make
  (modern multi-arch build; output `einsteinbinary_BRP4_linux_x86_64_cuda_custom`)
- `finalize_linux.sh` — strip + cuobjdump arch verification + copy to dist
- `setup_legacy_linux.sh`, `build_legacy_linux.sh` — cuFFT-shared legacy variant
  (`CUFFT_SHARED=1`, g++-11, sm_35+PTX; artifacts live in `dist/legacy/`)
- **ARM64 cross (x86_64 host → aarch64, Jetson targets)**:
  - `arm_env.sh` — arm64 multiarch (ports.ubuntu.com) + qemu-user binfmt
  - `arm_deps.sh` — cross gcc-14 + `:arm64` dev libs + CUDA 12.9 aarch64 redist → `/opt/cuda129-arm64/root`
  - `arm_boinc.sh` — hand-compiles BOINC lib/api archives for aarch64 → `/root/build/brp4-install-arm64`
    (OBJS must include `url` — app_ipc needs `escape_project_url`)
  - `arm_build.sh` — builds via `src/Makefile.linux.cuda.arm64`; nvcc/cicc run under qemu,
    host compile uses the native cross-g++ (`CXX=` MUST be forced on the command line,
    env vars override `?=`), fatbin archs sm_53/62/72/87/90 + compute_53
  - `arm_smoke.sh` — boots the aarch64 binary under qemu with the stub libcuda placed in
    `/usr/aarch64-linux-gnu/lib/libcuda.so.1` (qemu `-L` sysroots LD_LIBRARY_PATH!)
  - no bfd for arm64 multiarch → crash handler uses `src/compat/execinfo_stub.c`
- **Windows ARM64 cross (llvm-mingw, experimental — N1X-class hardware)**:
  - `wa_toolchain.sh` — installs llvm-mingw 20260616 → `/opt/llvm-mingw` (CUDA ships NO
    windows-arm64 toolkit pieces, so the host code is cross-compiled here)
  - `wa_deps.sh`, `wa_zlib.sh` — static zlib/iconv/xml2/gsl/fftw3f for
    aarch64-w64-mingw32 → `/root/wa/deps` (zlib needs `AR=$T-ar RANLIB=$T-ranlib`)
  - `wa_boinc.sh` — BOINC libs via `lib/Makefile.mingw MINGW=...`; overrides needed:
    `LIB_OBJ=` without `stackwalker_win.o` (x86-only CONTEXT fields) + stub archive members
    from `src/compat/stackwalker_arm64_stub.cpp` (StackwalkThread/StackwalkFilter/
    DebuggerInitialize/DebuggerDisplayDiagnostics); api lib is hand-compiled
    (boinc_api.cpp + graphics2_util.cpp — api/Makefile.mingw is EMPTY upstream);
    strlcpy/strlcat shim force-included (`src/compat/mingw_str_shim.h`);
    `-std=gnu++14` because diagnostics.cpp still calls std::set_unexpected;
    win_build/config.h FIRST on the include path or dlfcn.h leaks in
  - `wa_imports.sh` — extracts nvcuda/cufft imports from the x86_64 exe's import table,
    emits `src/win_arm64/*.def`; import libs via
    `llvm-dlltool -m arm64 -d x.def -D dll -l x.dll.a` → `/root/wa/imports`
  - build with `src/Makefile.win64.cuda.arm64` — reuses db.fat/dbhs.fat from the x86_64
    Windows tree (device fatbins are OS-agnostic, already sm_50..120+compute_50);
    embeds them via assembler `.incbin` (lld has no `ld -r -b binary`) keeping the
    `_binary_*_start/_end` symbols; links statically except nvcuda.dll+cufft64_11.dll
- `probe_winarm.sh` — redist JSON survey proving no windows-arm64 CUDA components exist
- `test_linux.sh` — full synthetic end-to-end run (exit 0 + candidates)
- `ckpt_test.sh`, `ckpt_kill9.sh` — checkpoint/restore tests (see notes)
- `check_signature.sh` — verify "Alperen Yavuz" embedded in all binaries
- `run_official_ter5.sh` — runs the OFFICIAL production exe on a real Ter5 input
  (proves current sband args need a newer non-public app)

## Hard-won gotchas
1. **PowerShell mangles** `$ | () *` inside `wsl bash -c "..."` — always use script files.
   Also avoid rewriting scripts with PowerShell `Set-Content` (CRLF corruption).
2. **nvcc host compiler**: EDG cannot parse gcc-15 headers → pass
   `--compiler-bindir /usr/bin/x86_64-linux-gnu-g++-14`.
3. `-U_GNU_SOURCE` required: glibc declares cospi/sinpi/rsqrtf with `__THROW`,
   CUDA's math headers clash otherwise. Plus `--allow-unsupported-compiler` for gcc-14.
4. **Static cuFFT link**: `libcufft_static_nocallback.a` + `libculibos.a`; rdc objects need
   device-link symbols that only the `_nocallback` static provides cleanly. For CUDA 11.8
   legacy we instead link shared `libcufft.so.10` with `-Wl,-rpath,'$$ORIGIN'` — single
   quotes are MANDATORY or the shell eats `$ORIGIN`. And use `LDFLAGS +=` not `=`.
5. Windows main build from the `brp4-src` symlink must pass
   `EINSTEIN_RADIO_INSTALL=/c/Users/Alp/brp4-install` ("Default Project" path contains a
   space and splits `-I` arguments). `make | tail` hides make failures (pipe status).
6. **Checkpointing**: BOINC `DEFAULT_CHECKPOINT_PERIOD = 300 s`. Standalone runs shorter
   than that never write `checkpoint.dat`. SIGTERM is ignored mid-run under standalone
   (no client quit_request); the app finishes gracefully. True restore is exercised by
   `kill -9` after the first checkpoint, then rerun (ckpt_kill9.sh).
7. Wrapper skips a pass if the output file already exists — delete stale outputs when
   re-testing.
8. An exported `CXX` in the environment silently overrides any makefile `CXX?=` —
   pass `CXX=` on the make command line for every cross build (it bit both ARM builds).
