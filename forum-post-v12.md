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
- NEW fermi build (CUDA 8.0): GTX 400/500 series, GT 610/620/630 (GF108/GF119),
  GT 430/440/530/540 — last Fermi driver branch: 390/391
- NEW kepler build (CUDA 10.2): GTX 600/700 series, GT 710/720/730/740,
  GTX Titan / Titan Black / K40 / K80 — last Kepler driver branch: 470/474
- modern build (CUDA 12.9, GTX 900 → RTX 50, driver r575+) now produced by
  the same pipeline, with a v1.2 banner
- Per-architecture packages: grab the one that matches your card, drop it
  in, done — plus an all-in-one router package that auto-picks (mixed rigs,
  or if you would rather not think about it)
- On mixed-GPU rigs the router follows BOINC's assigned GPU, so even a
  GT 710 + RTX 3080 pair routes correctly. Power users can force a build
  with the BRP4_BUILD environment variable (modern|kepler|fermi)

★ Downloads

Pick the package that matches your GPU family. Install only ONE of them —
they all declare the same app, so never install two.

⬤ GTX 900 → RTX 50 (modern), Windows: einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.2.zip
  https://github.com/alplix/brp4-cuda-port/releases/download/v1.2/einsteinbinary_BRP4_windows_x86_64_cuda_custom_v1.2.zip
⬤ GTX 900 → RTX 50 (modern), Linux: einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.2.tar.gz
  https://github.com/alplix/brp4-cuda-port/releases/download/v1.2/einsteinbinary_BRP4_linux_x86_64_cuda_custom_v1.2.tar.gz
⬤ GTX 600/700 + GT 7xx (kepler), Windows: einsteinbinary_BRP4_windows_x86_64_cuda102_kepler_v1.2.zip
  https://github.com/alplix/brp4-cuda-port/releases/download/v1.2/einsteinbinary_BRP4_windows_x86_64_cuda102_kepler_v1.2.zip
⬤ GTX 600/700 + GT 7xx (kepler), Linux: einsteinbinary_BRP4_linux_x86_64_cuda102_kepler_v1.2.tar.gz
  https://github.com/alplix/brp4-cuda-port/releases/download/v1.2/einsteinbinary_BRP4_linux_x86_64_cuda102_kepler_v1.2.tar.gz
⬤ GTX 400/500 + GT 61x/62x/63x (fermi), Windows: einsteinbinary_BRP4_windows_x86_64_cuda80_fermi_v1.2.zip
  https://github.com/alplix/brp4-cuda-port/releases/download/v1.2/einsteinbinary_BRP4_windows_x86_64_cuda80_fermi_v1.2.zip
⬤ GTX 400/500 + GT 61x/62x/63x (fermi), Linux: einsteinbinary_BRP4_linux_x86_64_cuda80_fermi_v1.2.tar.gz
  https://github.com/alplix/brp4-cuda-port/releases/download/v1.2/einsteinbinary_BRP4_linux_x86_64_cuda80_fermi_v1.2.tar.gz
⬤ ANY NVIDIA GPU / mixed rigs (router + all builds), Windows: einsteinbinary_BRP4_windows_x86_64_cuda_custom_router_v1.2.zip
  https://github.com/alplix/brp4-cuda-port/releases/download/v1.2/einsteinbinary_BRP4_windows_x86_64_cuda_custom_router_v1.2.zip
⬤ ANY NVIDIA GPU / mixed rigs (router + all builds), Linux: einsteinbinary_BRP4_linux_x86_64_cuda_custom_router_v1.2.tar.gz
  https://github.com/alplix/brp4-cuda-port/releases/download/v1.2/einsteinbinary_BRP4_linux_x86_64_cuda_custom_router_v1.2.tar.gz
⬤ Linux ARM64 / Jetson — unchanged from v1.1, that package is still the one
  to grab: https://github.com/alplix/brp4-cuda-port/releases/tag/v1.1

Router cost, measured: ~30–70 ms once per work unit (process spawn plus one
driver query) — zero effect on computation. The per-architecture packages
skip even that by shipping a single build.

★ Under the hood

- Every era build embeds native SASS for its own generations
  (fermi: sm_20 · kepler: sm_30/35/37 · modern: sm_50 → sm_120 plus family
  sections) and the lowest-arch PTX of its era, so newer GPUs keep working
  through the driver's JIT compiler
- The legacy toolchains were resurrected for this release: the CUDA 8.0 and
  10.2 installers predate modern Linux by a decade and needed a few bridges
  to run again — the whole process is scripted and reproducible
- The old __ldg read-only-cache lookups now fall back to plain loads on
  sm_20/sm_30, which never had that cache; the science path is untouched
  otherwise
- Driver floors are NVIDIA's choice, not mine: Fermi support ended at
  390/391, Kepler at 470/474, everything Maxwell and newer rides the
  current branches

★ Known limitation

- The current Ter5 "sband_dns" tasks belong to the newer BRP7 application
  whose options (--pb_min, ...) and source are not public yet — even the
  latest official public BRP4 exe rejects them. These builds target classic
  "-t bank" style work and standalone runs.

★ Test status

- cuobjdump-verified GPU code coverage on all six executables
  (three Linux + three Windows)
- All three builds on both platforms ran a complete work unit end-to-end on
  an RTX 5070 Ti — the legacy builds through their compute_35 / compute_20
  PTX JIT paths — with identical candidate lists
- Deployment was verified the way BOINC actually runs it: the router was
  exercised from a simulated slot that contained only itself and BOINC's
  init_data.xml, with the era builds sitting in the project directory
  exactly where the client expects them
- What I cannot test here: real Fermi and Kepler hardware. GTX 560, GT 730,
  GTX 660, Titan Black owners — this release exists for you, and your report
  is the one datapoint I cannot generate. If it works, tell everyone; if it
  doesn't, post the stderr and I'll fix it.

Same GPLv2+ license as the upstream source.

Feedback is very welcome — especially from the old-GPU crowd :)

Clear skies and fast GPUs!
