# NVIDIA performance: where it stands

Updated 2026-11-24.

Goal: a steady **33 ms/frame (30 fps)** in the world on the test PC,
**RTX 5060 Ti 16 GB, Ryzen 7 7700, Windows 11**.

Order of work:

1. CPU and VRAM bottlenecks (in progress).
2. GPU render bottlenecks (per-draw waits, shader costs).
3. Visual problems (missing geometry, low-bit colour), deferred for now.

## Current numbers

In-world, warm shader and pipeline caches, about 4,800–5,000 draws a frame,
default switches of [`scripts/bench/run.ps1`](../scripts/bench/run.ps1):

| Metric (per frame) | Now |
|---|---:|
| Frame time | **160–190 ms** (5.3–6.3 fps), median 166 ms |
| CPU preparing (title memory copies ~25 ms / ~118 MB, textures ~3–5 ms) | 50–58 ms |
| On the GPU | 102–118 ms |
| Copying back on the relay thread (~60 MB) | 40–50 ms |
| Submission waits, total | ~105 ms |
| of them: CPU changes under shader writes | ~58–64 ms |
| of them: in-flight list limit | ~35–41 ms |
| GPU queue busy (time with work of ours queued) | ~94 % |
| 3D engine utilization (Windows counters) | ~92 % |
| Board power while "busy" | 33–44 W (of ~180 W) |

### History

| State | ms/frame | fps |
|---|---:|---:|
| First combined build | ~385 | 2.6 |
| + relay thread + card-side hash fix | ~300 | 3.3 |
| + card copies of title buffers capped at 2048 MB | ~190 | 5.3 |
| + card-copy fetches on a copy queue of their own | ~166 | 6.0 |
| + batched GPU constant copies, GPU buffer copies | ~166 (median of 8 matched windows; was 190.75 on the same checkpoint) | 6.0 |
| Windowed indirect clamp (`VICTORY_INDIRECT_WINDOW=1`) | 194 (worse, kept off) | 5.2 |

## The biggest bottleneck: per-draw GPU pipeline drains

The GPU reads as busy but is mostly waiting. The 3D engine counts as ~92 %
busy, yet the board draws ~40 W and the memory controller sits near 5 %.
The CPU-side waits (CPU writes waiting on shader writes, the in-flight list
limit) mostly come from waiting for this slow GPU queue. Cutting them alone
shifts time into another wait.

The source is the indirect-argument clamp in
[`crates/victory-gpu/src/indirect.rs`](../crates/victory-gpu/src/indirect.rs)
(`record_clamp_as`). Titles issue mesh draws one argument record per call,
about 3,400–5,000 a frame. Before each one we record:

1. a global UAV barrier (null resource: wait for every earlier shader write)
   and a transition of the scratch buffer to UAV,
2. a one-group compute dispatch that clamps the record,
3. another global UAV barrier and a transition to `INDIRECT_ARGUMENT`,
4. the draw, then a transition back to `COMMON`.

That switches graphics → compute → graphics with full drains for every draw.
An earlier timing run measured 14–16 µs for a near-empty shadow draw, and a
serialized diagnostic charged ~85 ms a frame to indirect commands. That is
most of the GPU's ~105 ms.

Suggested next steps:

1. **Measure the ceiling.** In a diagnostics build,
   `VICTORY_BARRIER_TEST=indirect` drops the two global waits and keeps the
   state changes. Run it with `-Stats -AutoStart` against a baseline log.
2. **Clamp once per producer pass, not once per draw.** Clamp every record of
   an argument buffer in one dispatch after the pass that writes it, then let
   the draws read the clamped copy. The earlier windowed attempt regressed;
   find out why first (window tails, budget charging, or extra list breaks).
3. **Narrow the barriers.** Use a UAV barrier on the argument buffer instead
   of the null (global) one, and skip it when nothing in the list wrote the
   arguments since the last clamp.

## Other measured costs

1. **CPU writes into GPU-written buffers drain the queue.** ~60 ms/frame of
   waits; almost all hit the 512-fragment merge budget (single buffers can need
   more than 4,000 fragments). Pack exact byte deltas into masked word updates,
   coalesce by word, apply in queue order before the consumer.
2. **Recycle finished lists before CPU copy-back finishes.** ~35–41 ms/frame
   at the in-flight limit. Split retiring allocators and descriptors from the
   relay's publication of CPU-visible data.
3. **Track buffer ownership by range.** ~90–120 MB uploaded and ~60–80 MB
   fetched a frame. Tell GPU-written ranges from real CPU edits.
4. **Command preparation and texture churn.** ~50 ms/frame preparing, ~25 ms
   of that copying title memory.

## Reproducing a measurement

```powershell
$env:CARGO_TARGET_DIR='target-a'; cargo build --release -p victory
$env:VICTORY_LOG='info'; $env:VICTORY_FRAME_SAMPLES='1'; $env:VICTORY_TRACE_STALE='1'
.\scripts\bench\run.ps1 -Exe <title exe> -Target target-a -Log run-new.log -AutoStart
```

Then, in a second shell:

```powershell
.\scripts\bench\measure.ps1 -Log run-new.log -BaselineLog run-old.log -Survey
```

The parser waits for three matching warm windows (default 4,600–5,350
draws/frame, 300–380 draws dropped for a missing pipeline, none being built),
then reports medians of eight. Compare both frame time and total submission
wait, because work moves between wait categories. Use one process per
build, the same checkpoint, camera and switches. Use one target directory per
build, because a running exe locks its own.

## Design notes: lazy copy-back (not implemented)

- Keep flagged pieces pending instead of fetching them in `relay_card_back`.
  Mark their title pages `PAGE_NOACCESS` and fetch and merge on an access
  violation, then restore protection.
- Our own reads of title memory go through `read()` (`ReadProcessMemory`) in
  `host.rs`, which fails instead of faulting on such pages. It needs an
  explicit resolve hook.
- Deadlock hazard: callers hold shadow locks while reading title memory, so
  resolve before taking them, or per shadow under its own lock.
- Protection hazard: view memory is already guarded read-only by `watch.rs`.
  Pending state must live under the same `GUARDS` lock.
- Merging needs writable pages, so another thread can briefly see a
  half-merged piece.
