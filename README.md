# victory-nv

**An Xbox Series X|S compatibility layer for Windows, tuned for NVIDIA GPUs.**

victory-nv runs a title's x86-64 code natively inside its own process. It
supplies the console platform underneath: loader, runtime services, file
streaming, input, audio, a Direct3D 12 back end and a console-GPU →
DXIL shader recompiler. It is a community fork of
[VIctory](https://github.com/Marvisak/VIctory). It merges several downstream
forks and focuses on frame time on NVIDIA hardware.

> [!IMPORTANT]
> This repository contains **no proprietary code, data or assets**. You
> supply your own legally obtained files at runtime. See
> [docs/asset-policy.md](docs/asset-policy.md). Pull requests that add
> such material are rejected by policy and by an automated check.

[![License: GPL v3+](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![Platform: Windows x64](https://img.shields.io/badge/platform-Windows%20x64-lightgrey.svg)
![Status: work in progress](https://img.shields.io/badge/status-work%20in%20progress-orange.svg)

---

## Contents

- [Status and performance](#status-and-performance)
- [Getting started](#getting-started)
- [Project layout](#project-layout)
- [Benchmarking](#benchmarking)
- [Debugging](#debugging)
- [Contributing](#contributing)
- [Credits](#credits)
- [License](#license)

## Status and performance

**Work in progress: not playable at full speed yet.**

Test machine: Windows 11, **NVIDIA RTX 5060 Ti 16 GB**, **AMD Ryzen 7 7700**.
The numbers below were measured in-world with warm caches, ~4,800–5,000 draws
per frame.

| | |
|---|---|
| **Frame time now** | **160–190 ms** (median 166 ms, **~6 fps**) |
| **Target** | **33 ms** (30 fps) |
| Starting point of this fork | ~385 ms (2.6 fps) |
| Menus and front end | full speed (30 fps) |

Where a frame's time goes today:

| Per frame | ms |
|---|---:|
| On the GPU | 102–118 |
| CPU preparing submissions (title-memory copies ~25 ms, textures ~3–5 ms) | 50–58 |
| Copying shader results back to title memory (relay thread, overlapped) | 40–50 |

**Biggest bottleneck:** the GPU's 3D engine shows ~92% busy but draws only
~40 W (of ~180 W). It is stalled, not working. Every indirect draw (~4,000–5,000
a frame) gets its own argument-clamp compute dispatch wrapped in global UAV
barriers, so the GPU switches graphics → compute → graphics with full pipeline
drains for each draw. The analysis, history, other measured costs and next steps
are in **[docs/nvidia-performance.md](docs/nvidia-performance.md)**.

Progress so far:

| Change | ms/frame |
|---|---:|
| First combined build | ~385 |
| Relay thread lands results as the GPU finishes; card-side hash fix | ~300 |
| GPU-memory copies of large title buffers (2 GB cap) | ~190 |
| Card-copy fetches on a dedicated copy queue | ~166 |
| Batched GPU constant fills and GPU buffer copies (matched benchmark: 190.75 → 166.30) | ~166 |

Known problems: a few hundred draws a frame are dropped where a shader or
pipeline does not translate yet (missing geometry). Ray-traced lighting does
not run yet ([docs/fork-ray-tracing.md](docs/fork-ray-tracing.md)). Some
colour precision is low. Memory use is high (~24 GB).

## Getting started

**Requirements:** Windows 10/11 x64, a CPU with AVX2, a Direct3D 12 GPU with
shader model 6.6 and mesh shaders, and Rust (the version is pinned in
`rust-toolchain.toml`). Titles also need several GiB of free Windows commit at
startup. If `crashes.log` reports Windows error 1455, enlarge the paging file.

```powershell
git clone https://github.com/mravatins/victory-nv
cd victory-nv
cargo xtask install-hooks                # asset-policy check on every commit
copy victory.example.toml victory.toml   # then set your paths (outside the repo)
cargo test --workspace                   # needs no title data
cargo run -p victory -- config           # check your paths
```

Build and run:

```powershell
cargo build --release -p victory
target\release\victory.exe run <title dir>\<title exe> --execute
```

The window caption shows the frame rate. Saves, settings and `crashes.log`
live under `%LOCALAPPDATA%\victory\data`, and derived data (shader and
pipeline caches) under `%LOCALAPPDATA%\victory\cache`. Both can be changed in
`victory.toml`.

**Recommended NVIDIA switches** (set by `scripts/bench/run.ps1` unless
`-Plain`):

```powershell
$env:VICTORY_RELAY='2'
$env:VICTORY_CARD_BUFFERS_MIN_MB='1'
$env:VICTORY_CARD_BUFFERS_MB='2048'   # for a 16 GB card
```

**Input:** XInput pads. With no pad connected, the keyboard acts as one while
the window has focus:

| Keys | Pad |
|------|-----|
| W A S D / I J K L | left / right stick |
| arrows | D-pad |
| Enter, Backspace, X, Y | A, B, X, Y |
| Q / E, Z / C | shoulders, triggers |
| F / H | stick clicks |
| Esc, Tab | Menu, View |

**Commands:**

```
victory inspect <exe|dll> [--imports] [--exports]
victory census [paths...] [--missing] [--strict]
victory lib-exports <import.lib> [--list]
victory shader-info [paths...] [--verbose] [--disasm]
victory translate [paths...] [--validate] [--pipelines] [--list] [--jobs N]
victory run <exe> [--execute] [--unimplemented trap|zero] [--strict]
            [--console series-x|series-s] [-- <title arguments>]
victory config
```

## Project layout

| Path | What |
|---|---|
| `apps/victory` | the command-line front end |
| `crates/victory-loader`, `victory-pe` | PE loading, imports, in-process execution |
| `crates/victory-hle` | runtime services: kernel, storage, input, audio, users, saves |
| `crates/victory-gpu` | Direct3D 12 back end: lists, shadows of title memory, relay, textures |
| `crates/victory-shader` | console GPU ISA → DXIL recompiler and optimizer |
| `crates/victory-pipeline` | pipeline creation and the on-disk pipeline library |
| `crates/victory-formats` | archive, compression and texture formats |
| `crates/victory-core`, `victory-game` | shared types, configuration, per-title glue |
| `xtask` | repository tooling (`cargo xtask policy`, hooks) |
| `scripts/bench` | automated benchmark launcher and log comparison |
| `docs` | architecture, asset policy, performance, ray tracing |

The design is described in [docs/architecture.md](docs/architecture.md).

## Benchmarking

There is an automated, hands-free benchmark. `-AutoStart` taps A once, then
holds A in 10-second presses, which gets through profile selection and skips
intros. The log parser then compares warm in-world windows of two runs:

```powershell
$env:VICTORY_LOG='info'; $env:VICTORY_FRAME_SAMPLES='1'; $env:VICTORY_TRACE_STALE='1'
.\scripts\bench\run.ps1 -Exe <title exe> -Target target -Log run-new.log -AutoStart
.\scripts\bench\measure.ps1 -Log run-new.log -BaselineLog run-old.log -Survey
```

Please attach before/after numbers from this to performance pull requests.
See [docs/nvidia-performance.md](docs/nvidia-performance.md#reproducing-a-measurement).

## Debugging

A release build has no debugging aids. Build them in with:

```powershell
cargo build --profile diag -p victory --features diagnostics   # target\diag\victory.exe
```

| Variable | Effect |
|----------|--------|
| `VICTORY_LOG=<target>=debug,...` | debug and trace output (release logs info and above) |
| `VICTORY_STACKS=20,60` | every thread's stack at those seconds |
| `VICTORY_WATCH=<rva>,...` | logs a title u32 when it changes |
| `VICTORY_KEYS=30:Enter,35:X` | presses keys at those seconds, focus or not (`key:hold` seconds optional) |
| `VICTORY_CRASH_SAVE=<rva>:<len>,...` | saves title memory to the cache folder on a crash |
| `VICTORY_CAPTURE=<dir>` | saves presented frames (`VICTORY_CAPTURE_FRAMES=<list>` to pick) |
| `VICTORY_DUMP_TARGETS=1` | with the above, saves every render target of those frames |
| `VICTORY_D3D12_DEBUG=1` / `VICTORY_D3D12_GBV=1` | D3D12 debug layer / GPU-based validation |
| `VICTORY_D3D12_DRED=1` | on a GPU failure, the allocation hit and commands in flight |
| `VICTORY_GPU_TIMING=1` | each list timed on its own; slow lists logged with their slowest commands |
| `VICTORY_BARRIER_TEST=indirect\|groups\|both` | leaves out selected waits to measure their cost |
| `VICTORY_SKIP_PIPELINES=<hash>,...` | omits draws whose pipeline contains a listed shader hash |
| `VICTORY_PIPELINE_WAIT_MS=24` | per-frame wait for background pipeline creation (default 500) |
| `VICTORY_D3D12_WARP=1` | software adapter (slow; cannot reset the driver) |
| `VICTORY_SHADER_OPT=0` | turns off the translated-shader optimizer |

Most speed features sit behind environment switches. Each one is documented
in a comment where it is read. Every build appends crashes and host GPU
failures to `crashes.log`.

## Contributing

Contributions are welcome. Read **[CONTRIBUTING.md](CONTRIBUTING.md)** first.
In short: never commit proprietary material, keep `cargo clippy` and
`cargo test` clean, and include benchmark numbers with performance changes.
This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

Building your own project on top of this? Fork away. Keep the GPL-3.0-or-later
license and the credits in [CREDITS.md](CREDITS.md).

## Credits

victory-nv stands on the work of many people. See **[CREDITS.md](CREDITS.md)**
for the full list. The main sources:

- **[VIctory](https://github.com/Marvisak/VIctory)** by Marvisak and
  contributors: the base of everything here.
- **[victory-fork](https://github.com/fxceless/victory-fork)** by fxceless and
  contributors: rendering, streaming and speed work this fork builds on.
- **[victory-amd](https://github.com/myokex/victory-amd)** by myokex: texture
  view, dispatch-splitting and pipeline-list fixes.
- **[VItoriaBr](https://github.com/uiliannn/VItoriaBr)** by uiliannn: pointed
  to the array-texture LOD query error. The fix here was written for this tree.
- **[XCL](https://github.com/ivall/xcl)** by ivall: a behavioural reference.
  No code was copied.

Developed with [Claude Code](https://claude.com/claude-code).

## License

**GPL-3.0-or-later.** See [LICENSE](LICENSE). This applies to all code in
this repository, including code inherited from the projects above, which use
the same license. The BCPack format tables in
`crates/victory-formats/src/bcpack-tables.bin` are format data, not covered by
this license; see [docs/asset-policy.md](docs/asset-policy.md#the-one-exception).

This is an independent, non-commercial interoperability project. It is not
affiliated with, endorsed by or sponsored by Microsoft or any title's developer
or publisher. All trademarks belong to their owners.
