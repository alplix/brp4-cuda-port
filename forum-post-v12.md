# Forum post draft — v1.2 (paste into the existing BRP4 thread as an update,
# or use the parts marked TITLE for a new thread)

TITLE: ✧ Pulsar hunting at warp speed ✧ Special BRP4 CUDA builds ✧

Hello fellow sky crunchers :)

Sixty years ago Jocelyn Bell's ribbon recorder traced the first flicker of a
spinning neutron star across a hundred meters of paper. Today your GPU does
the same trick with a few million signal templates per work unit — and it
would be a shame to leave any GPU out of the hunt.

When I posted the first special BRP4 CUDA builds here, they only covered
modern GPUs (GTX 900 and newer). But some of the most loyal BOINC crunchers
out there are still running Kepler cards in a second rig, or a trusty Fermi
in the garage. v1.2 is for them: the same re-coded BRP4 application, compiled
by the CUDA toolkits of the era, so the whole Fermi → Blackwell family can
pulsar hunt at warp speed.

★ What's new in v1.2

- A tiny router program now starts the right binary for your GPU
  automatically — one package, every NVIDIA card, no manual picking
- **fermi build** (new, CUDA 8.0): GTX 400/500 series, GT 610/620/630,
  GT 430/440/530/540 — needs the last Fermi driver (390.x)
- **kepler build** (new, CUDA 10.2): GTX 600/700 series, GT 710/720/730/740,
  GTX Titan / Titan Black / K40 / K80 — needs the last Kepler driver (470.x)
- modern build unchanged in spirit (CUDA 12.9, GTX 900 → RTX 50, driver
  r575+), now built with the same pipeline and a v1.2 banner
- On mixed-GPU rigs the router follows BOINC's assigned GPU, so even
  GT 710 + RTX 3080 pairs route correctly (BRP4_BUILD env var overrides)

★ Downloads

⬤ Windows 10/11 x64 — einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.2.zip
  (router + 3 builds + cuFFT DLLs + app_info/app_config + README)
⬤ Linux x86_64 — einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.2.tar.gz
  (router + 3 builds + era cuFFT libs + app_info/app_config + README)
⬤ Linux ARM64 / Jetson — unchanged from v1.1, grab that package from the
  v1.1 release page

★ Under the hood

- Each era build embeds native SASS for its own generations
  (fermi: sm_20 · kepler: sm_30/35/37 · modern: sm_50 → sm_120 + family
  sections) plus the lowest-arch PTX of its era, so any newer GPU can JIT it
- The legacy toolchains were resurrected for this build: CUDA 8.0 and 10.2
  (their installers predate modern Linux and needed a few bridges), with
  era-matched GCC front-ends so the 2016/2019 compilers accept modern hosts
- The old `__ldg` read-only-cache lookups now fall back to plain loads on
  sm_20/sm_30 — the science path is untouched otherwise
- Driver floors are set by NVIDIA, not by me: Fermi support ended at
  390.x, Kepler at 470.x, everything Maxwell+ continues on current branches

★ Known limitation

- Current Ter5 "sband_dns" tasks belong to the newer BRP7 application whose
  options (`--pb_min`, ...) and source are not public yet — the official
  public BRP4 exe rejects them too. These builds target classic "-t bank"
  style work and standalone runs.

★ Test status

- cuobjdump-verified SASS/PTX coverage for all six executables
- All three Linux and all three Windows builds ran a complete work unit
  end-to-end on an RTX 5070 Ti (the legacy builds via their compute_35 /
  compute_20 PTX JIT paths) with identical candidate lists
- RTX 5070 Ti + modern build: full end-to-end, exit 0
- **What I cannot test here: real Fermi and Kepler hardware.** GTX 560,
  GT 730, GTX 660, Titan Black owners — this release exists for you, and
  your report is the one datapoint I cannot generate. If it works, tell
  everyone; if it doesn't, post the stderr and I'll fix it.

Feedback is very welcome — especially from the old-GPU crowd :)

Clear skies and fast GPUs!
