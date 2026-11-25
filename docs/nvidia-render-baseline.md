# NVIDIA render baseline candidate

Build `d09dbaeb` on `codex/nv-render-baseline` from the tested
`bench-fxceless` source. It includes the four local GPU file changes on top of
`c098dd4a`. Use the Series X profile and the same save and camera for each
comparison. These captures used a GeForce RTX 5060 Ti 16 GB.

## Prologue window corruption

The corruption is reproducible with `VICTORY_BVH_HOLD=0`. Rectangular patches of
the exterior appear below the window and over the lower wall. The room still
shows its wall, posters and clothing detail. An earlier run with
`VICTORY_BVH_HOLD=1` made those areas substantially darker while suppressing
ray-tracing traversal against unbuilt structures. Keep both lighting and tile
coverage in the visual comparison.

The original local frame capture is `shots-blocks/shot-2285-225256`. Event
numbers below are the first column in its `events.txt`. Resource addresses
identify objects in that capture only.

| Event | Shader | Observation |
| --- | --- | --- |
| 344 | `6bb493a39685ddcc` | Writes the shared 28,800-byte tile buffer at guest address `0x10020e0000`. |
| 349 | `8cb27ccf2d50c606` | Writes a 57,600-byte buffer read by the second resolve dispatch. |
| 362–363 | `2dc364df5d3278b8`, `940c2635dc1312f4` | Both read the shared tile buffer and write `0x1d5ef7770a0` and `0x1d5ef776d60`. The color capture at event 373 already contains the exterior patches. |
| 440 | `34fb51b8a0312e82` | Reads those outputs. A later pre-composite capture of `0x1d54027e520` has the same pattern. |

The two resolve shaders both accepted translation and passed the Windows DXIL
validator with the host set to 32 lanes. The native headers specify Wave32
for both tile writers and both resolve shaders. The resolve disassembly reads tile
entries using the workgroup index before computing image coordinates. The capture leaves the shared tile data, the indirect dispatch records, and
the individual writes of each resolve shader unresolved.

## Reproduction settings

Build with `cargo build --locked --release -p victory`. Run
`victory.exe run <title-exe> --execute --console series-x --unimplemented trap`
with a local `victory.toml`. The benchmark used the following environment
settings from the fxceless fast profile and left traversal holding disabled.

```text
VICTORY_LEVELS_ON_DEMAND=1
VICTORY_ASYNC_SUBMIT=1
VICTORY_QUEUE2=1
VICTORY_INDIRECT_WINDOW=1
VICTORY_TEXTURE_NO_WAIT=1
VICTORY_MERGE_GAP=64
VICTORY_MERGE_RUNS=4096
VICTORY_STAGING_POOL=0
VICTORY_COPY_PLAIN=1
VICTORY_JOIN_PARTS=1
VICTORY_BACK_OWN_VIEW=1
VICTORY_INDIRECT_GATHER=1
VICTORY_CARD_REHASH_RUNS=1
VICTORY_CARD_BUFFERS_MIN_KB=64
VICTORY_CARD_BUFFERS_MB=1280
VICTORY_BVH_HOLD=0
VICTORY_LOG=info
```

The steady window in `bench-fxceless_nv_baseline_warm.log` from
`23:25:19` through `23:25:56` UTC gave a median of 98.6 ms per frame
(about 10.1 fps) across eight five-second reports with 4,764–4,841 draws per
frame. The earlier `run-nv-x-windows2.log` benchmark returned 111.1 ms
per frame (9.0 fps) across eight similarly sized reports. The runs used
different renderer settings, so this comparison does not isolate a speedup.

## Verification

The baseline was rebuilt as a standard release. The reference executable in
`bench-fxceless` includes the diagnostics feature, which is another difference
when comparing those runs.

Commit `3b4169bc` preserves scalar work on far-jump exit paths. The existing
Wave64 tests passed after the fix. The nine compute shaders checked from the
prologue trace emitted identical DXIL before and after the fix.

The shader suite passed 222 tests after excluding two LDS floating-point
atomic tests following a stalled run. The GPU suite passed 184 tests after
excluding the indirect-budget test, which still fails intermittently
when separate workgroups compete for the same budget.
