# The frame-rate plan (PF) — 2026-09-25

**Question.** Where does a frame of a `voxel_game` game go, how much of it can the kit
win back, and what is the ceiling Flutter itself sets, on desktop and on a phone?

**How it is answered.** One benchmark, run before the first change and after every
step, so every step is judged by numbers taken the same way (§Method). The steps are
ordered by what the baseline showed to cost the most, cheapest wins first; the heavy
ones (PF13–PF15) run only if the numbers still ask for them when their turn comes.

**What was known before measuring** (the investigation of 2026-09-24, from reading the
code): flutter_scene records its GPU commands on the UI thread, inside paint, so the
simulation, the chunk uploads and the scene's encoding share one thread; each lit draw
costs ~9 calls into native code and ~20 native allocations; a vertex is 72 B on the GPU
(48 from the mesher, 24 of zeros flutter_scene adds); opaque draws are sorted by geometry
before depth, and nothing culls what is hidden behind terrain; Flutter GPU has no compute,
no indirect or multi-draw, no packed vertex formats and no buffer-to-buffer copy.

---

## Method

`dart tool/run_benchmark.dart` (from this folder's root) builds
`packages/voxel_game/example/lib/benchmark.dart` in **release**, runs each scenario
`--repeat` times round-robin with a cooldown between runs, and prints the medians. `--out`
keeps every run's line (JSONL, committed under `docs/perf/`); `--compare A B` prints two
of those files side by side.

**The game** is the kit's example (`packages/voxel_game/example/lib/main.dart`, seed 2024,
two biomes, trees, ores, water), with a creative player and natural spawning off. The
window is fixed at 1600×900 points (`--window`, which the example's macOS runner reads).

**The scenarios** (`Scenario` in `benchmark.dart`). Each fills the window (every chunk of
the `(2r+1)²` square meshed and the streamer idle), waits 2 s, then records 12 s:

| Scenario | Camera | What it loads |
|:--|:--|:--|
| `orbit:r` | 16 m over the spawn, one full turn, pitch −0.35 | the steady cost of a loaded window at radius r |
| `fly:r` | 16 m over the spawn, flying east at 16 m/s | chunk streaming: a new row of chunks every second |
| `mobs:r` | on the ground, one full turn | 40 creatures around the player, half of them hunting it (paths, rigs, shadows) |

The sky runs its normal day (it starts at the spec's `startTime`), so the sun's steps and
their shadow re-renders are part of every run.

**The metrics** (`FrameStats` / `FrameReport` in `packages/voxel_game/lib/src/loop/`):

| Metric | Source | Reads as |
|:--|:--|:--|
| `fps` | presented frames (`FrameTiming`s) ÷ seconds | what the player sees; capped by the display's refresh |
| `hitches` | frame intervals over 1.5 refresh periods | frames the display showed twice |
| frame p99 | interval between the vsyncs that started two presented frames | pacing |
| **GPU p50 / p99** | an empty command buffer submitted after the scene's; its completion callback minus the end of the encoding | the GPU's time per scene frame (an upper bound: it includes the callback's delivery and any wait behind the previous frame) |
| UI p50 / p99 | `FrameTiming.buildDuration` | the whole UI thread: simulation, chunk uploads, HUD, scene encoding |
| encode p50 | `Scene.renderViews` wall time (`MeasuredScene`) | flutter_scene recording GPU commands |
| sim p99 | `VoxelGame.frame` wall time | steps, streaming uploads, sky |
| raster p99 | `FrameTiming.rasterDuration` | Flutter compositing the scene's image |
| fill ms | game ready → window filled | generation and meshing on the workers |
| faces | faces meshed by fill time | the terrain load |
| RSS MB | `ProcessInfo.maxRss` at the end | peak memory |

**Why GPU time and not only fps.** At the display's cap fps only says "under budget"; the
GPU time is the headroom, and it is what a 120 Hz display or a phone spends. A frame is
GPU-bound when GPU p50 is near the refresh period while UI p50 is far below it.

**Rules for a comparable number.** Release build, never debug (JIT adds 13–72%,
`examples/voxel_game_minecraft/docs/PERFORMANCE_VS_GODOT_2026-09-11.md`). Same window,
same display, on AC power, other heavy apps closed. Medians of 3 runs; a change is real
only when it is larger than the spread (±) of both sides. The display's refresh rate is in
every line (`refreshHz`): compare only lines taken at the same rate.

**Validity: the screen must be unlocked.** A locked Mac keeps rendering the game's frames
behind the lock screen, but the display never shows them: presentation runs at 60 Hz
whatever the display can do, and `gpuMs` is paced by the lock screen (it stayed at 12–13 ms
at radius 6 whether the frame drew 100% or 56% of the pixels, with or without shadows). A
Metal System Trace of that state (`xcrun xctrace record --template 'Metal System Trace'`,
which needs the **profile** build: release lacks `get-task-allow`) recorded GPU work from
`loginwindow` only. So, for a run taken with the screen locked, the UI, encode, sim, fill
and RSS columns hold, and fps, hitches and GPU are indicative at best. Since `906ffac`
`tool/run_benchmark.dart` records `screenLocked` in every line and says so in its summary
and comparison. **The baseline and the PF1 runs of 2026-09-25 (≈00:40–01:40) were taken
locked** (verified during the PF1 runs; the display ran at 60 Hz from the first run, and
it reached 120 Hz on 2026-09-11), before the script could record it.

**`gpuMs` still needs a check with the screen unlocked**: its values against a Metal
System Trace of the profile build (the `metal-gpu-intervals` table, summed per frame). If
it tracks, it stays; if it does not, the trace becomes the GPU column's source.

**The final comparison (PF17) is an A/B in one sitting**, unlocked, which makes the locked
baseline above a preview rather than the reference: the harness is committed at `67da3ac`,
so the before is rebuilt from that commit in a worktree and run alternately with the after.

```bash
git worktree add --detach /tmp/voxel_bench_pf0 67da3ac
(cd /tmp/voxel_bench_pf0 && flutter pub get)
dart /tmp/voxel_bench_pf0/tool/run_benchmark.dart --out /tmp/pf17_before.jsonl   # absolute paths:
dart tool/run_benchmark.dart --out /tmp/pf17_after.jsonl                         # each script runs from its own root
# second round in the other order (after, then before), same --out files, then:
dart tool/run_benchmark.dart --compare /tmp/pf17_before.jsonl /tmp/pf17_after.jsonl
git worktree remove /tmp/voxel_bench_pf0
```

**Phones.** Not measured yet: no device was attached on 2026-09-25. `benchmark.dart` takes
its flags from `--dart-define=BENCH="--scenario=orbit --radius=6"` on a platform that
cannot pass arguments; the line it prints is the same.

## Baseline

Taken at `PF0` (see Progress), before any optimisation. The raw lines are
`docs/perf/pf0_baseline.jsonl`.

| run | n | fps | hitches | frame p99 ms | GPU p50 ms | GPU p99 ms | UI p50 ms | UI p99 ms | encode p50 ms | sim p99 ms | raster p99 ms | fill ms | faces | RSS MB |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| orbit:6 | 3 | 61.0 ±0.30 | 0 | 16.7 | 14.1 ±0.62 | 15.6 | 0.89 | 3.83 | 0.76 | 0.14 | 1.01 | 484 | 185130 | 296 |
| orbit:12 | 3 | 59.0 ±2.62 | 22 | 33.3 | 16.4 ±1.17 | 75.6 | 2.39 | 5.36 | 2.19 | 0.06 | 22.5 | 1328 | 663953 | 519 |
| fly:6 | 3 | 60.9 ±0.05 | 0 | 16.7 | 13.5 ±0.32 | 16.3 | 1.18 | 4.97 | 0.94 | 1.59 | 1.55 | 475 | 185130 | 307 |
| fly:12 | 3 | 60.7 ±2.41 | 0 | 16.7 | 12.1 ±0.13 | 20.5 | 2.24 | 7.37 | 2.04 | 3.31 | 1.12 | 1220 | 663953 | 530 |
| mobs:6 | 3 | 35.3 ±0.41 | 83 | 100 | 17.1 ±2.18 | 90.1 | 11.1 | 77.9 | 3.38 | 74.6 | 6.01 | 480 | 185130 | 344 |

Apple M2 Pro · macos · 1600x900 @2.0x · 60.0 Hz · commit a4b988c

Medians of 3 runs (± half the spread). Every run was presented at the display's 60 Hz: the
built-in display ran at 60 Hz that day, although it reached 120 Hz on 2026-09-11 (the
minecraft example's study), so its refresh setting changed in between. A 120 Hz run is a
separate baseline, not comparable with this one.

**What it says.**

- **The GPU is the wall.** At radius 6, with nothing moving but the camera, the GPU spends
  14 of the 16.7 ms a 60 Hz frame has; the UI thread spends under 1. A 120 Hz frame (8.3 ms)
  is out of reach at any radius as the kit draws today, and a phone's GPU is several times
  slower than an M2 Pro's.
- **Radius 12 stutters from the GPU, not the CPU.** GPU p99 75 ms against p50 16: a few frames
  cost four or five normal ones (22 hitches in 36 s). The raster thread's p99 (22 ms) is the
  composite waiting on those frames. The periodic suspect is the shadow cascades re-rendered
  on every step of the sun.
- **Creatures are the CPU wall.** 40 of them take the frame rate to 35: the simulation's p99
  is 75 ms (the hunters' paths to a player they cannot reach) and the UI thread's median is 11 ms.
- **Streaming is not a problem on this machine at 60 Hz.** Flying a chunk a second leaves
  UI p99 at 5–7 ms and no hitches.

---

## Steps

Each step is one commit, suite green, measured with the benchmark afterwards; its row in
Progress carries the numbers that moved.

**Order after PF1, by what the baseline showed.** The CPU wall is the creatures (sim p99
75 ms), and a locked screen still measures CPU honestly, so the next steps are the ones
that move CPU columns: PF5 → PF6 → PF7 → PF9 → PF3 → PF2 → PF4 → PF8 → PF10 → PF11 → PF12.
The GPU steps (PF13–PF15) wait for an unlocked sitting and the `gpuMs` check, because their
gate is a GPU number.

| ID | Step | Packages | Expected to move |
|:--|:--|:--|:--|
| PF0 | Measurement: `FrameStats`, `MeasuredScene`, the benchmark entry, `tool/run_benchmark.dart`, the baseline | voxel_game, example | — |
| PF1 | `GraphicsSpec`: render scale, anti-aliasing, shadow cascades / resolution / distance, the sun's step, presets for desktop and phone; the far plane at the fog's edge | voxel_game, voxel_scene | GPU |
| PF2 | Chunk upload: the frame budget checked before each apply and lowered; 16-bit indices when they fit; bounds computed on the worker | voxel_engine, voxel_scene | UI p99, hitches in `fly` |
| PF3 | Interpolation: poses and the camera drawn between two steps with the loop's `alpha`; the look applied per frame | voxel_game | pacing at >60 Hz |
| PF4 | HUD: rebuilt when what it shows changes, behind a `RepaintBoundary` | voxel_game | UI p50 |
| PF5 | Block queries: `getBlockXYZ` / `lightAt` by shifts and an int key, no record per call | voxel_engine | sim |
| PF6 | Mob brains: repaths staggered, A* with int keys and reused buffers, the hunt's target scan | voxel_engine, voxel_game | sim p99 in `mobs` |
| PF7 | Mob bodies: one geometry per rig part per species, shadows only near, no animation far or off screen | voxel_game, voxel_scene | GPU and encode in `mobs` |
| PF8 | Worker pool: sized for the device; the neighbour ring sent without a copy | voxel_engine | fill ms, UI p99 |
| PF9 | Per-step garbage: `VoxelBody`, raycasts, rig parts, list copies | voxel_engine, voxel_game, voxel_scene | sim p99 |
| PF10 | Audio: recipes synthesised off the UI isolate | sound_recipes, voxel_game | UI p99 at start |
| PF11 | Net: one encoding per broadcast, edits batched per step | voxel_engine, voxel_game | host UI with peers |
| PF12 | Selection outline: one mesh instead of twelve | voxel_scene | encode |
| PF13 | Packed terrain vertex: a custom geometry and vertex shader, 8–16 B a vertex instead of 72 | voxel_engine, voxel_scene | GPU, RSS |
| PF14 | Chunk regions: several chunks' surfaces in one draw | voxel_scene | encode, GPU |
| PF15 | Greedy meshing, the per-voxel tint moved into the shader | voxel_engine, voxel_scene | GPU |
| PF16 | flutter_scene upstream: sort opaque draws front to back, skip absent vertex streams | — (proposal) | GPU |
| PF17 | Final measurement against the baseline, the ceiling on desktop and phone | docs | — |

PF16 is written as a proposal and sent upstream only with the owner's go-ahead: it is an
outward-facing action. Windows and Linux cannot render in release on Flutter 3.47.0 at all
(Flutter GPU is switched on from the runner only from 3.47.1); that is recorded in the
ledger, not in this plan.

## Progress

| ID | Status | Commit | Result |
|:--|:--|:--|:--|
| PF0 | done | `67da3ac` (measurement) · this commit (baseline) | the baseline above; `docs/perf/pf0_baseline.jsonl` |
| PF1 | done | `906ffac` | Desktop preset = the old look, so no change expected but the far plane: none measurable at radius 6/12 (orbit:12 GPU p99 75.6 → 73.4, fps 59.0 → 54.3, both inside the ±2.5 spread). The variants (`docs/perf/pf1_graphics_variants.jsonl`, orbit:12) name the spikes: GPU p99 73 ms with the desktop look, 18–21 ms and **0 hitches** with any of shadows off, FXAA, render scale 0.75 or the phone preset; a 3° sun step leaves them (74.6). So radius 12 saturates the GPU with pixels (MSAA × Retina × the lit shader × four cascades), and the sun's steps are not the cause. Screen locked during these runs: see §Validity. |
| — | tooling | this commit | `run_benchmark.dart` records whether the screen was locked; §Validity written. |

**Where the work stopped (2026-09-25, context budget).** Last commit: this one. Next step:
**PF5** (block queries), then the order above. Learned and not in the code: (1) the display
ran at 60 Hz all night because the screen was locked, so no run so far saw 120 Hz; (2) the
release build cannot be traced by Instruments, the profile build can; (3) `screencapture`
from the terminal returns a black image (no Screen Recording permission), so a visual check
needs the owner or an in-app capture; (4) in zsh, `rm -f dir/x*.jsonl` with no match aborts
an `&&` chain.
