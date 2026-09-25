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
| GPU latency p50 / p99 | an empty command buffer submitted after the scene's; its completion callback minus the end of the encoding | how long a frame waited and ran on the GPU, the queue included: **not the GPU's cost** (§Validity); a GPU-bound frame reads about three refresh periods |
| **GPU ms/frame** (`--trace`) | a Metal System Trace of the profile build: the union of the app's `metal-gpu-intervals` over the recorded seconds, ÷ Flutter's composites in them | **the GPU's cost per frame**; the budget is 8.3 ms at 120 Hz |
| GPU busy % (`--trace`) | the same union ÷ the recorded seconds | near 100: the GPU is what caps the frame rate |
| UI p50 / p99 | `FrameTiming.buildDuration` | the whole UI thread: simulation, chunk uploads, HUD, scene encoding |
| encode p50 | `Scene.renderViews` wall time (`MeasuredScene`) | flutter_scene recording GPU commands |
| sim p99 | `VoxelGame.frame` wall time | steps, streaming uploads, sky |
| raster p99 | `FrameTiming.rasterDuration` | Flutter compositing the scene's image |
| fill ms | game ready → window filled | generation and meshing on the workers |
| faces | faces meshed by fill time | the terrain load |
| RSS MB | `ProcessInfo.maxRss` at the end | peak memory |

**Why a GPU number and not only fps.** At the display's cap fps only says "under budget";
the GPU's cost per frame is the headroom, and it is what a 120 Hz display or a phone spends.
That cost is not in the app's line: flutter_scene gives no GPU timestamps, and the latency
column counts the queue. It comes from a Metal System Trace of the profile build:
`--trace` (macOS) runs every scenario under `xcrun xctrace` and adds `gpuTrace` to its line
(§Validity). Instruments cannot attach to a release build, so a traced run is a profile
build's (its fps is within 1% of release's at `orbit:6`): its lines go in their own file,
compared only with other traced lines. Each traced run leaves nothing behind (the trace
and the ~1 GB raw recording are deleted), and every line says which build it was (`mode`),
checked against the one the script built: xctrace launches an app by bundle id, and once
started a stale debug build of it that never exited and filled the disk.
A frame is GPU-bound when the trace shows the GPU busy nearly all the time while UI p50 is
far below the refresh period.

**Rules for a comparable number.** Release build, never debug (JIT adds 13–72%,
`examples/voxel_game_minecraft/docs/PERFORMANCE_VS_GODOT_2026-09-11.md`). Same window,
same display, on AC power, other heavy apps closed. Medians of 3 runs; a change is real
only when it is larger than the spread (±) of both sides. The display's refresh rate is in
every line (`refreshHz`): compare only lines taken at the same rate.

**Validity: the screen must be unlocked.** A locked Mac keeps rendering the game's frames
behind the lock screen, but the display never shows them: presentation runs at 60 Hz
whatever the display can do, and the GPU latency is paced by the lock screen (it stayed at 12–13 ms
at radius 6 whether the frame drew 100% or 56% of the pixels, with or without shadows). A
Metal System Trace of that state (`xcrun xctrace record --template 'Metal System Trace'`,
which needs the **profile** build: release lacks `get-task-allow`) recorded GPU work from
`loginwindow` only. So, for a run taken with the screen locked, the UI, encode, sim, fill
and RSS columns hold, and fps, hitches and GPU are indicative at best. Since `906ffac`
`tool/run_benchmark.dart` records `screenLocked` in every line and says so in its summary
and comparison. **The baseline and the PF1 runs of 2026-09-25 (≈00:40–01:40) were taken
locked** (verified during the PF1 runs; the display ran at 60 Hz from the first run, and
it reached 120 Hz on 2026-09-11), before the script could record it.

**The app's GPU number is a latency, not the GPU's cost** (checked 2026-09-25, unlocked,
120 Hz). A Metal System Trace of the profile build running `orbit:6` recorded the GPU 98.6%
busy and **9.98 ms of GPU work per composited frame** (the union of the app's
`metal-gpu-intervals` over the recorded 10 s, 988 frames, the run at 99.7 fps), while the
app read 29.5 ms at p50: the frame's work plus about two more frames of queue. It also moved
the wrong way in an experiment: with the HUD's blurred text shadows removed, fps rose
100.7 → 103.5 (outside the ±0.1 spread) and the latency went 29.7 → 64.2 ms. So the column
was named `gpuMs` until this was known and is `gpuLatencyMs` since (the committed lines were
migrated, values untouched); it still says whether the queue is full, and nothing about
the GPU's cost, which only the trace gives. The trace's own column: Instruments labels
overlapping passes together (`RenderPass & Gaussian Blur Filter`), so a label's time is not
that pass's cost; only the union of all of them is.

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

**Phones.** `dart tool/run_benchmark.dart --android <adb serial> --cooldown 20` builds the
APK, installs it and runs each scenario on the device: the flags travel in the launch
intent (`am start --esal dart_entrypoint_args`, which `FlutterActivity` hands to `main`), the
line comes back from logcat (a release build's `stdout` reaches neither logcat nor, on
macOS, anything but the process's own stdout, hence `_report` in `benchmark.dart`). The
phone runs in landscape and full screen. Each line records `deviceTempC`, the battery's
temperature before the run: a phone throttles when hot, so its runs drift more than the
Mac's, and a longer cooldown is part of the method there. The keyguard counts as a locked
screen. iOS, which cannot pass arguments, takes `--dart-define=BENCH="--scenario=orbit
--radius=6"`; it has no runner support in the script yet.

## Baseline

Taken at `PF0` (see Progress), before any optimisation, **with the screen locked**
(§Validity): a preview, kept for its CPU columns. The reference is §Baseline at 120 Hz below.
The raw lines are `docs/perf/pf0_baseline.jsonl`.

| run | n | fps | hitches | frame p99 ms | GPU latency p50 ms | GPU latency p99 ms | UI p50 ms | UI p99 ms | encode p50 ms | sim p99 ms | raster p99 ms | fill ms | faces | RSS MB |
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

**What it said** (read with §Validity: "GPU" here is the latency column, paced by the lock
screen; §Baseline at 120 Hz says which of these still hold).

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

## Baseline at 120 Hz (the reference)

Taken 2026-09-25, 12:30–13:30: screen unlocked, the Mac's display at 120 Hz (ProMotion), on
AC; the phone on USB. Raw lines: `docs/perf/pf1_mac120_*.jsonl`, `docs/perf/pf1_s24_*.jsonl`.

**Mac, before and after PF1, in one sitting.** `67da3ac` (the harness, before any
optimisation) rebuilt in a worktree and run alternately with `eeb4a3d` (PF1, the desktop
preset), three rounds, the order swapped each round (`pf1_mac120_ab_*.jsonl`; the before's
`+dirty` is its Linux and Windows plugin registrants, regenerated by the build, fixed in
`a4b988c`). Medians of 3, ± half the spread:

| run | fps `67da3ac` | fps `eeb4a3d` | hitches | UI p50 ms | encode p50 ms | sim p99 ms | raster p99 ms |
|:--|--:|--:|--:|--:|--:|--:|--:|
| orbit:6 | 100.0 ±1.3 | 100.9 ±0.1 | 284 · 283 | 0.71 · 0.71 | 0.61 · 0.61 | 0.04 · 0.03 | 21.2 · 21.0 |
| orbit:12 | 68.6 ±1.4 | 71.2 ±3.4 | 472 · 464 | 1.94 · 1.98 | 1.84 · 1.83 | 0.09 · 0.10 | 34.5 · 33.1 |
| fly:6 | 118.6 ±0.2 | 118.6 ±0.2 | 29 · 33 | 0.66 · 0.67 | 0.57 · 0.57 | 0.78 · 0.74 | 9.6 · 9.7 |
| fly:12 | 97.5 ±5.2 | 96.9 ±0.3 | 276 · 302 | 1.81 · 1.82 | 1.68 · 1.69 | 2.27 · 1.88 | 19.8 · 19.8 |
| mobs:6 | 51.9 ±2.5 | 48.4 ±3.1 | 244 · 223 | 8.24 · 8.48 | 3.25 · 3.24 | 62.5 · 71.6 | 18.1 · 20.1 |

Apple M2 Pro · 1600×900 @2x · 120 Hz. The GPU's cost (`--trace`, one run each,
`pf1_mac120_trace.jsonl`): **orbit:6 9.99 ms a frame, the GPU 98.7% busy; fly:6 8.32 ms,
97.2%**.

**Galaxy S24 Ultra, the desktop look against the phone preset.** SM-S928B, Snapdragon 8
Gen 3 (SM8650), Android 16, Impeller on Vulkan, 2340×1080 (832×384 points @2.81), 120 Hz;
the APK of `797de1d`; three rounds alternating the looks, 20 s cooldown, the battery 29.9 →
35.2 °C over the 24 runs with no drift between the first round and the last. The desktop
look is `67da3ac`'s (PF1's desktop preset moved only the far plane, which the Mac's A/B
shows is worth nothing), so its column is the phone's *before*:

| run | fps desktop look | fps phone preset | UI p50 ms | encode p50 ms | sim p99 ms | RSS MB |
|:--|--:|--:|--:|--:|--:|--:|
| orbit:6 | 36.1 ±2.6 | **98.8 ±5.2** | 21.7 → 5.7 | 20.5 → 4.9 | 0.19 → 0.09 | 365 → 367 |
| orbit:12 | 23.4 ±2.0 | **60.2 ±2.5** | 38.3 → 12.1 | 37.0 → 11.3 | 0.20 → 0.09 | 635 → 629 |
| fly:6 | 40.0 ±1.5 | **115.4 ±5.4** | 18.7 → 5.5 | 17.4 → 4.6 | 4.39 → 1.81 | 385 → 385 |
| mobs:6 | 19.7 ±0.7 | **26.4 ±0.3** | 33.4 → 15.4 | 9.4 → 7.3 | 78.0 → 79.2 | 483 → 457 |

**What it says** (this replaces the locked baseline's reading).

- **PF1 moved nothing on the Mac, as designed** (every row inside its spread), and is worth
  **2.6–2.9× on the phone**: 36 → 99 fps at orbit:6, 23 → 60 at orbit:12, 40 → 115 flying.
  The kit picks the phone preset on Android and iOS by default, so that is what a phone
  game gets today.
- **The Mac is GPU-bound at 120 Hz.** At orbit:6 the GPU is busy 98.7% of the time at 10 ms
  a frame against the 8.3 ms a 120 Hz frame has, while the UI thread spends 0.7 ms. Flying
  costs 8.3 ms and holds 117–119 fps; radius 12 falls to 69–71. So on the Mac the GPU steps
  (PF13, PF15) are what reach 120, and `--trace`'s ms a frame is their gate.
- **On the phone the UI thread was the wall.** With the desktop look the scene's encoding
  takes 20 ms at radius 6 (0.6 on the Mac for the same draws). The phone preset cuts it 4×,
  more than the passes it saves (two shadow cascades instead of four: 5 passes → 3), so
  part of what `encodeMs` holds on Android is waiting (for a buffer or the swapchain), not
  recording; a Perfetto trace would split the two. Either way draws × passes is the phone's
  budget: PF14 (fewer draws), PF7 and PF12 move it.
- **Creatures are the CPU wall on both**: sim p99 62–72 ms on the Mac, 78–79 on the phone,
  whatever the look; mobs:6 runs at 48–52 fps on the Mac and 20–26 on the phone.
- **Between sittings the Mac's fps moves by up to 10%**: orbit:12 read 71 in the A/B and 78
  an hour later with the same build (`pf1_mac120_hud_blur_on.jsonl`). A step is judged by an
  A/B in one sitting, the before rebuilt in a worktree (§Validity), never against a file of
  another day.
- **The HUD's blurred text shadows cost ~3% at orbit:6** (100.7 → 103.5 fps without them,
  `pf1_mac120_hud_blur_*.jsonl`; inside the noise at radius 12 and flying): four `Text`s,
  each a three-pass Gaussian blur in Impeller. A PF4 item, not a wall.

---

## Steps

Each step is one commit, suite green, measured with the benchmark afterwards; its row in
Progress carries the numbers that moved.

**Order after PF1, by the 120 Hz baseline.** The creatures are the CPU wall on both
platforms, so PF5 → PF6 → PF9 first, then PF7 (their bodies: draws on the phone, GPU on the
Mac). Then the draws the phone encodes, PF14, and the GPU the Mac spends, PF15 then PF13,
each gated by its number (UI p50 on the phone, `--trace`'s ms a frame on the Mac). Then
PF3 → PF2 → PF4 → PF8 → PF10 → PF11 → PF12. Each step is measured on the Mac and, when it
moves the UI thread or the GPU, on the phone.

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
| — | tooling | `eeb4a3d` | `run_benchmark.dart` records whether the screen was locked; §Validity written. |
| — | measurement | `2187947` · `797de1d` · `41c2695` · `b82a370` · `344270e` | The example runs on Android and iOS; `--android` runs the benchmark on a phone; the app's GPU number is `gpuLatencyMs` (a latency, checked against Instruments); `--trace` gives the GPU's cost per frame; §Baseline at 120 Hz, the reference for every step from here. |
| PF5 | done | this commit | `getBlockXYZ` / `lightAt` by shifts and an int key: 41 → 14.5 ns and 66 → 32 ns a call (a microbenchmark, AOT). A/B on the Mac at 120 Hz, unlocked, `cdea482` against this commit, three rounds alternated (`docs/perf/pf5_mac120_ab_*.jsonl`): **mobs:6 fps 50.4 → 91.4** (runs 45.5–50.9 → 89.1–92.2), **sim p99 66.4 → 11.3 ms**, UI p99 69.5 → 14.7, frame p99 83 → 25. So the creatures' wall was mostly the block query their paths call: A* reads `getBlockXYZ` for every cell it opens. Hitches rose 246 → 350 because twice the frames are presented; they are counted, not a rate. |
| PF5 | phone | this commit | Galaxy S24 at 120 Hz, A/B against `e77e82b` (the tree `cdea482` had, reworded), three rounds alternated, `mobs:6` and `orbit:6` as control (`docs/perf/pf5_s24_*_ab_*.jsonl`): **no change**. Phone preset: mobs:6 23.8 → 23.7 fps, sim p99 80.5 → 75.6 (runs 76–85 → 69–76), steps a second 51–53 → 53–56; desktop look: 18.6 → 18.9 fps. Why the Mac moved and the phone did not: `FixedStepLoop` runs up to `maxSteps` (4) steps a frame, so a frame slower than a step banks more steps and the next frame is slower still. On the Mac PF5 took a step's cost under the point where that feeds itself (sim p50 ~3 ms after); on the phone a step still costs ~18 ms and the loop stays capped at 4 steps (4 × 18 ≈ the 72–80 ms p99, and fewer than 60 steps a second). So sim p99 reads the cap there, not a step's cost: PF6 needs a per-step number (sim ms ÷ steps) to be judged on the phone. |
| — | measurement | `a5d1ebd` | `FrameReport.stepMs`: each tick's simulation time over the steps it ran, a step's own cost whatever the loop banks; `--compare` shows its p50 and p99. |
| PF6 | replans | this commit | Stopwatches in the step (temporary, not committed) put 5.8 of a 6.0 ms step (Mac, `mobs:6`) in `Pathfinder.find`, at **11.2 searches a step** where 40 mobs replanning every 0.6 s make 1.1: `Mob._steer` replanned at once whenever its path ran out, and an unreachable goal (a hunter at the player, who floats a metre up in creative) gives a partial path that runs out every step, each search spending all 400 nodes. The brains (`think` + behaviours, the Hunt scan with them) cost 0.03 ms a step and the rigs 0.12: neither is worth touching. Now a path is replanned every 0.6 s, sooner (≥ 0.2 s) only when the goal moved 1.5 m, and each mob's timer starts at a random phase. A/B on the Mac at 120 Hz against `a5d1ebd`, three rounds alternated (`docs/perf/pf6_mac120_ab_*.jsonl`; the after build still had the stopwatches, its lines carry `prof`): **step p50 7.82 → 0.27 ms**, step p99 11.1 → 8.8, sim p99 13.9 → 8.6, UI p50 7.1 → 3.8, **fps 84.2 → 93.5**, frame p99 30.7 → 23.9. 0.58 searches a step remain, 0.6 ms each (they still spend 400 nodes): the next half of PF6. |

**Where the work stopped (2026-09-25).** Last commit: PF5. Next step: **PF6** (mob
brains). After PF5 sim p99 in `mobs:6` is 11 ms on the Mac but still ~75 ms on the phone,
where the loop is capped at 4 steps a frame (see PF5's phone row): judge PF6 by a step's
own cost, which `FrameReport` does not report yet. A phone run takes `-- --graphics=phone`,
or `benchmark.dart` draws the desktop look. Learned and not in the code: (1) the screen was
locked all night, so the first baseline is a preview; the reference was taken unlocked at
120 Hz the next day; (2) Instruments traces only a profile build, and `xctrace` leaves a
~1 GB raw recording per run in the user's temp dir (the script deletes it; by hand, delete
`$TMPDIR/instruments*.ktrace`); the disk had ~27 GB free; (3) `screencapture` works from
the VS Code terminal once VS Code has Screen Recording permission (granted 2026-09-25), and
`adb exec-out screencap -p` captures the phone; (4) the phone's adb serial is
`RQCY706J2YV` (Galaxy S24 Ultra), its screen timeout 10 minutes; (5) in zsh, `rm -f
dir/x*.jsonl` with no match aborts an `&&` chain.
