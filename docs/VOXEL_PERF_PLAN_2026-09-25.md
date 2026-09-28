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
| view judder | `FrameStats.addView`, the camera once a frame: RMS of (the frame's view motion ÷ its `dt` ÷ the run's mean speed − 1), motion being the forward's turn plus the eye's travel over 10 m | how evenly the view moves: 0 moves by the time that passed, ~1 moves every other frame |
| still frames | the frames whose view moved less than a quarter of the mean speed | frames that showed the view the one before showed |
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
checked against the one the script built. xctrace launches the app by its bundle id, which
LaunchServices resolves to any copy it knows (registered, or indexed by Spotlight), whatever
path it was handed: it once started a stale debug build that never exited and filled the
disk, and in PF15 the release build and the other worktree's. So while it records, the
script unregisters every other copy and renames it out of its `.app` extension, registers the
tree's profile build, refuses the run unless the trace's launched process is that build, and
kills the processes of the app it left behind (xctrace leaves one suspended every run).
A frame is GPU-bound when the trace shows the GPU busy nearly all the time while UI p50 is
far below the refresh period.

**Rules for a comparable number.** Release build, never debug (JIT adds 13–72%,
`examples/voxel_game_minecraft/docs/PERFORMANCE_VS_GODOT_2026-09-11.md`). Same window,
same display, on AC power, other heavy apps closed. Medians of 3 runs; a change is real
only when it is larger than the spread (±) of both sides. The display's refresh rate is in
every line (`refreshHz`), and so is the window's pixel ratio (`dpr`): compare only lines
taken at the same rate and ratio. With the external 1080p display connected the window opens
on it at `dpr` 1.0, a quarter of the Retina's pixels at 2.0: `orbit:6` then traces 5.7–5.9 ms
of GPU a frame, 70% busy and held at 120 fps, against 8.8–8.9 at 2.0 (PF15).

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

### PF3, the design (2026-09-28)

**What is wrong today.** `VoxelGame.frame` runs `FixedStepLoop.advance`, 60 steps a second,
and everything a frame draws is written by the step: `NodeBody.syncNode` (the player, the
creatures, drops, projectiles, remote players), `RigInstance.place` (a rig's facing), and
the player's `yaw` / `pitch`, which `PlayerEntity.tick` takes from `InputMap.takeLook`.
`ViewCamera.camera` reads them in paint. At 120 Hz half the frames run no step, so the
view and every body stand still for a frame and move a whole step the next: the world is
drawn at 60 Hz on a 120 Hz display. The view bob and the third-person orbit advance by
`game.time`, which moves only in steps, so they stand still with it. `FixedStepLoop.alpha`
exists and nothing reads it. The benchmark cannot see any of this: its camera is posed from
`onTick`, inside the step, so it moves at 60 Hz whatever the display does, and fps, hitches
and frame p99 say when frames were presented, not what they showed. PF3 changes what a
frame shows, not when it is presented, so those columns hold its cost (the interpolation is
UI-thread work every frame), not its gain.

**The measurement first, in its own commit.** `FrameStats.addView(eye, forward)`, called by
`ViewCamera.camera` once a frame, keeps how far the view moved that frame: the angle the
forward turned plus the eye's travel over 10 m (a point 10 m ahead moves on screen by about
that angle); `addFrame` takes the frame's `dt`. The report's `view` holds `judder`, the RMS
over the frames of (the frame's speed ÷ the run's mean speed − 1), 0 for a view that moves
by exactly the time that passed and ~1 for one that moves every other frame, and
`stillFrames`, the frames that moved less than a quarter of the mean. The benchmark drives
the view as a player does: `orbit` and `mobs` turn through the look at a steady rate
(`InputMap.turn`, a held stick, which `takeLook` integrates over its `dt`;
`playWithoutCapture` so that the game reads it), and `fly` places the player by `game.time`
(a walk moves in steps),
not by the wall clock the steps happened to run at. The A/B's before is that commit.

**What keeps the previous state.** `NodeBody` (voxel_scene) holds two poses of its node, the
one the last step set and the one before it, each a position, a yaw and a pitch (a node's
scale is its model's business). `syncNode({at, yaw, pitch})` sets this step's pose (`at`
defaults to `position`; a turn left out keeps its value); `beginStep()` makes the last pose
the one the frames draw from, and `VoxelGame.step` calls it on every body before anything
moves; `drawNode(alpha)` writes `from + (to − from)·alpha` into the node (the yaw the short
way round), once a frame from `VoxelGame.frame`, and skips a body whose two poses are equal
and already drawn. A body's first `syncNode`, and `syncNode(snap: true)` (a respawn, a
placement), set both poses, so nothing streaks from the origin or across the map.
`drawnPosition` is where the node stands this frame. A frame is drawn one step behind the
simulation, the price of interpolating (16.7 ms), for motion as even as the display.

**Where `alpha` enters.** In `VoxelGame.frame`: after `_loop.advance`, every body is drawn
at `_loop.alpha` (the player, the mobs, the entities, remote players among them); then the
hand (`FirstPersonView.update`) and, in paint, the camera read drawn values.
`VoxelGame.drawnTime`, `time − step · (1 − alpha)`, is the game time a frame shows; between
two frames it moves by the frame's `dt`. `ViewCamera` advances the view bob and the orbit's
easing by it instead of `time`, and its eye is `PlayerEntity.drawnEye`. The selection
outline around a creature follows the creature's drawn box, once a frame
(`PlayerEntity.drawOutline`); around a block nothing changes.

**The rigs.** A rig's facing moves from `RigInstance.place` (the rig's root) to its owner's
node: `place` keeps the topple, the scale, the squash and the shake, and the owner passes
`yaw: rig.yaw` to `syncNode`, so a body turns as smoothly as it moves. The limbs
(`RigPart`s) stay posed at the step's rate, and so does a death's topple: the rigs cost
0.12 ms a step on the Mac (PF9's stopwatches), and posing them every frame at 120 Hz would
double that for a swing of a few degrees a step.

**The look, once a frame, and rule 14.** `VoxelGame.frame`, while `gameplay`, drains the look
once, before the steps (`input.takeLook(dt)`, handed to `PlayerEntity.look`, which drops it
while the player is dead or not yet placed); `PlayerEntity.tick` no longer takes it. The
view turns at the display's rate, a frame's latency instead of a step's, and the steps of
that frame aim and walk with the newest yaw. The camera's turn is never interpolated, only
its eye. Rule 14 keeps polling in the fixed step so that one press has one reader; the look
is not a button but a motion, which the event handlers only add to and one reader drains,
never inside an event callback. The rule gains that sentence in PF3's commit: the step
reads the buttons, the frame drains the look. The stick's share is integrated over the
frame's `dt`, as the mouse's already is over its events.

**What does not change.** The step: 60 Hz, `FixedStepLoop` as it is, nothing paused (rule
12); the buttons, read by the step alone; the network, which sends the step's pose and yaw;
a headless game, whose frame draws its nodes too (cheap, and what the tests read).

**Judged by** `view judder` and `still frames` on `orbit:6`, `fly:6` (`fly:12` too on the
Mac) and `mobs:6`, ~1 and half the frames before at 120 Hz, near 0 after; and by what it
costs: UI p50 and p99, step p99, frame p99 and hitches. A/B against the measurement commit,
on the Mac and the phone. Tests: `NodeBody`'s two poses (voxel_scene); in voxel_game, that
the drawn eye moves by `alpha` between two steps, that a frame with no step still turns the
view, and that a respawn does not streak.

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
| PF6 | A* | this commit | `Pathfinder` keys a cell by an int (its offset from the start, 12 bits an axis), finds a node by one `Map<int, int>` into lists (key, g, parent, closed) reused from one search to the next, and reads each cell's blocks once, with no `IVec3` made in the loop. Against the old code on 1200 random searches (far and negative coordinates, fences, water, lava, mud, budgets 100–600): the same paths, 228 → 141 µs a search (JIT). A/B on the Mac at 120 Hz against `364c6b4`, three rounds alternated (`docs/perf/pf6_mac120_ab_{364c6b4,astar}.jsonl`): **step p99 8.65 → 4.73 ms** (runs 8.6–9.7 → 4.6–4.9), sim p99 8.5 → 4.6, UI p99 12.4 → 8.7. fps is no judge here: 37–103 on both sides, the third round low on both, and the GPU the limit once the step is cheap. The Hunt's target scan is left as it is: the brains measured 0.03 ms a step. |
| PF6 | phone | this commit | Galaxy S24 at 120 Hz, phone preset, the whole of PF6 (`a5d1ebd` against `2a79328`), three rounds alternated (`docs/perf/pf6_s24_phone_ab_*.jsonl`): **mobs:6 fps 24.0 → 58.2** (runs 22.0–25.9 → 58.0–58.6), **step p50 8.62 → 0.58 ms**, step p99 26.2 → 19.8, sim p99 70.4 → 19.8, steps a second 53–56 → 60 (the loop no longer falls behind), UI p50 23.6 → 12.3, frame p99 83 → 33. Hitches 287 → 698 only because 2.4× the frames were shown at 120 Hz. Encode p50 7.7 → 10.9: the mobs move now, and more frames are encoded. Step p99 still ~20 ms on the phone, the steps that run a search spending the whole budget. |
| — | bug | `d34acab` | `Wander` read `Mob.pathBlocked` before the plan for its new goal, so a wanderer whose last walk was blocked dropped every later goal; `walkTo` clears the verdict for a goal more than `Mob.replanDistance` from the planned one. The example's sheep wander, so `mobs:6` carries more walking from here (0.58 → 0.78 searches a step): the next A/B takes `d34acab` as its before. |
| PF6 | budget | `5853760` | Stopwatches in the step (temporary, not committed; Mac, `mobs:6`) put **every one of the slowest 1% of steps at ~4.6 ms of A\***, 13–15 searches in one step, while a search costs 0.30 ms at p50 and 0.38 at p99. The random phase `attached` gives each mob was lost at its first plan (a new goal plans after 0.2 s whatever the phase, and the timer restarts at zero), so the hunters that saw the player in one step replanned together every 0.6 s, as every hunter does when the player moves 1.5 m. Now a step runs at most `Mob.searchesPerStep` (3) searches and a mob whose plan is due when they are spent plans on a later step. A/B against `d34acab`, three rounds alternated, unlocked (`docs/perf/pf6_{mac120,s24_phone}_ab_{d34acab,budget}.jsonl`): Mac at 120 Hz **step p99 4.65 → 1.15 ms** (runs 4.6–5.1 → 1.14–1.15), sim p99 4.5 → 1.1, UI p99 8.1 → 5.5, fps 102 on both (the GPU is the limit); Galaxy S24, phone preset, **step p99 19.6 → 4.5 ms** (runs 19.1–20.5 → 4.3–5.2), sim p99 19.6 → 6.2, UI p99 30.2 → 20.1, frame p99 33 → 25, fps 58 on both (UI p50 12.4 ms, 10.7 of it the scene's encoding). The searches a step are the same, only spread. |
| PF9 | measured | — | The same stopwatches: a step without a search costs **0.24 ms at p50 and 0.32 at p99** on the Mac (brains 0.03, movement 0.06, rigs 0.12, player 0.02, items, liquids, spawner and pruning ~0), so the per-step garbage PF9 names has no cost inside the step there. If it costs anything it is as GC pauses elsewhere in the UI thread, which only a trace (Perfetto on the phone, a Dart timeline) would show: PF9 waits for one, behind PF7. A phone line with a `prof` field did not parse: logcat cuts a line at ~1000 characters, so a profile on the phone goes on its own line. |
| PF7 | shared meshes | `e770ef0` | **Where the encode went** (flutter_scene's own profile, `--dart-define=FLUTTER_SCENE_PROFILE=true`, in a temporary build with `print` sent to the benchmark's output; nothing committed): with 40 creatures the **shadow pass** was the cost, 6.14 ms a frame on the Galaxy S24 (phone preset, 2 cascades) against 0.98 at `orbit:6`, and 2.42 against 0.06 on the Mac (4 cascades); the colour pass barely moved (+0.2 ms on the Mac, 3.3 ms on the phone with or without creatures). Every creature part was a geometry of its own (260 for 40 creatures) and flutter_scene 0.23 batches only items with the identical geometry and material (`opaqueBatchEnd` / `depthBatchEnd`), so each part was a draw in every cascade every frame: a moving creature is a dynamic caster the shadow cache (`shadowStatic`) cannot keep. Now `RigModel.of(rig, halfWidth, height)` builds a look at a size once and every `RigInstance` shares its meshes: **260 → 8 geometries**, each part one instanced draw a pass; the profile's shadow pass **2.42 → 0.45 ms** on the Mac and **6.14 → 1.46** on the phone, the colour pass 146 draws → 96 for 140 instances (Mac). A/B against `3d56938`, three rounds alternated, unlocked, 120 Hz (`docs/perf/pf7_{mac120,s24_phone}_ab_{3d56938,shared}.jsonl`): Mac **encode p50 3.40 → 1.11 ms** (runs 3.38–3.42 → 1.03–1.16), UI p50 3.67 → 1.45, RSS 338 → 300 MB, fps 102 on both (the GPU is the limit); Galaxy S24, phone preset, **fps 58.3 → 68.2** (runs 54–59 → 68–72), **encode p50 10.7 → 6.2 ms**, UI p50 12.4 → 9.5, RSS 481 → 419 MB, battery 32–33 °C on both sides. **The step read slower after** (Mac p50 0.24 → 0.31, p99 1.16 → 2.03; phone 0.63 → 1.03, 4.45 → 8.35) although no code it runs changed: rerun with the CPU held busy (two `yes` on the Mac, four through `adb shell` on the phone, `docs/perf/pf7_{mac120,s24_phone}_cpuload_*.jsonl`) the step is the same on both sides (Mac p50 0.26–0.30 → 0.22–0.28, p99 1.19 → 1.13–1.15; phone 0.51 → 0.51–0.54, p99 3.6–4.0 → 4.2–4.6). It is the clock: with less work a frame, the CPU runs slower. On the phone that also caps the frame rate: held busy, the after runs **92–99 fps, encode 3.6 ms, UI p50 4.7–5.1** against 68 fps unloaded, the before 60.5 either way. The rest of PF7 is left: the creatures' shadows now cost ~0.5 ms on the phone (1.46 against `orbit:6`'s 0.98), and their rigs 0.12 ms a step on the Mac (PF9 measured), so shadows only near and no animation far would win less than the noise. |
| — | ADPF probe | this commit (numbers; the prototype is not committed) | **The phone's clock, tried through Android's Dynamic Performance Framework: no gain, a loss at `orbit`.** Flutter 3.47.5 creates no hint session: no `PerformanceHint` in the engine's source (`engine/src/flutter`), its release `libflutter.so` or `flutter.jar`. `dumpsys performance_hint` on the Galaxy S24 (Android 16) shows the process's only session is HWUI's (tag 2: the main thread, which runs Dart since the UI and platform threads merged, `RenderThread`, `hwuiTask0/1`; target 16.7 ms), fed only when HWUI draws a view, and the game draws into a SurfaceView; `1.raster` is in no session. A prototype in the benchmark's entry created one through the NDK by `dart:ffi` (`APerformanceHint_createSession` in `libandroid.so`, API 33+: the UI and raster threads, target the display's period, 8.33 ms; it showed in `dumpsys` as tag 4), fed every frame from a `WidgetsFlutterBinding` subclass (release batches `FrameTiming` a second at a time, too late for a governor). A/B against `68c3619`, three rounds alternated, phone preset, 120 Hz. **(A) the UI thread's work** (`handleBeginFrame` to the end of `handleDrawFrame`, step and encode inside; `docs/perf/adpf_s24_phone_ab_{68c3619,hint}.jsonl`): `mobs:6` fps 82.4 · 66.6 · 68.1 → 62.9 · 76.0 · 74.8, UI p50 8.78 → 8.55, encode p50 6.13 → 6.18: the ranges overlap and the UI thread is no faster; `orbit:6` **107.7 · 104.4 · 110.0 → 92.9 · 96.1 · 92.6 (−14%)**, GPU latency p50 9.38 → 11.7 ms, UI p50 5.63 → 5.74. **(B) the interval between frames' starts**, clamped at 3 targets, the period the pipeline holds, to say "120 Hz is missed" even when the UI thread is under target (`docs/perf/adpf_s24_phone_ivl_*.jsonl`): `mobs:6` 67.0 · 68.9 · 74.8 → 62.2 · 71.2 · 69.2, UI p50 9.47 → 10.4; `orbit:6` 99.3 · 101.2 · 96.4 → 95.3 · 90.3 · 92.1 (−7%), GPU latency p50 9.58 → 11.3. Neither buys what four busy loops do (UI p50 ~5, 92–99 fps), and both slow the GPU at `orbit`: with a session of its own the app hands the vendor's power HAL a CPU budget it seems to take from elsewhere. Not a step. A variant reporting the GPU's time too (`AWorkDuration`, API 35) needs a per-frame GPU duration the Dart side does not have. |
| PF14 | regions | this commit | `VoxelChunkView` draws chunks in 2 × 2 regions: one node a region, one geometry a surface, the chunk offsets baked into the positions (`MergedSurface`), 16-bit indices while they fit, bounds taken during the copy; a chunk's apply or removal rebuilds its region from the surfaces the view keeps. flutter_scene's profile, `orbit:6`: colour-pass **draws 85–101 → 39–40** on the Mac, encode 326–454 → 164–189 µs; on the phone the colour pass cost 3.7–4.0 ms for 95–99 draws before (~31 µs a draw, ~4 on the Mac). A/B against `70ca8dc` (the tree of `6d990fb`), three rounds alternated, 120 Hz, Mac (`docs/perf/pf14_mac120_ab_{70ca8dc,regions}.jsonl`), no overlap between runs: **encode p50 orbit 0.63 → 0.31 ms** (0.62–0.64 → 0.30–0.31), mobs 1.10 → 0.75, fly 0.58 → 0.29; UI p50 −29 to −44%, UI p99 orbit 1.91 → 0.90, mobs 4.44 → 2.20; fps unchanged (GPU-bound); the costs: **fly UI p99 2.29 → 2.89** (a region's rebuild when a chunk streams in) and **RSS +34 to +53 MB** (the kept surfaces). Galaxy S24, phone preset, 120 Hz, three full rounds alternated against `70ca8dc` (the after is `3577f2a`, PF14's tree; `docs/perf/pf14_s24_phone_ab_{70ca8dc,regions}.jsonl`, which replace the partial files of the first attempt), no run lost, the battery 30.7–33.5 °C on both sides: **mobs fps 72.2 → 87.4** (runs 70.7–72.7 → 79.5–90.8), encode p50 6.27 → 4.50, UI p50 9.29 → 6.18, UI p99 20.2 → 17.3, GPU latency p50 15.8 → 10.6; **orbit 91.2 → 114** (87.1–99.5 → 112–116), encode 5.15 → 3.82, UI p50 5.92 → 4.84; **fly 116 → 117** (at the display's rate on both), encode 4.59 → 3.50, UI p50 5.41 → 4.57. The costs: **fly step p99 2.08 → 6.01 ms** (2.03–2.71 → 5.01–6.29; `stepMs` holds the streaming uploads, so this is a region rebuilt when a chunk arrives), fly UI p99 9.6 → 11.6 (ranges overlap), RSS +11 to +30 MB; mobs step p99 7.90 → 9.70, with no chunk streaming and no code of the step changed: the clock, as in PF7. **With the CPU held busy** (four `yes`, `docs/perf/pf14_s24_phone_cpuload_*.jsonl`) the A/B says nothing: the battery climbed 33.6 → 40.4 °C over the 18 runs and one build ran `orbit` at 37–86 fps, the first round, the coolest, the fastest on both sides. The busy-CPU check works for a few runs (PF7's), not for three rounds of three scenarios on a phone. |
| — | tooling | this commit | **The runs the phone lost were crashes of the app**, not the runner's: `dumpsys activity exit-info` recorded `APP CRASH(NATIVE)`, signal 11, for each, and the dropbox kept their tombstones (20:10, 20:13, 20:20): a null dereference in the Adreno driver's `vkCmdBeginRenderPass` under Flutter GPU's `RenderPass.begin`, the process 1–2 s old, 20 s after the previous run's clean exit (the cooldown), so neither a process still alive at `am start -S` nor logcat's buffer. It is `KL-008` in the ledger. The runner read only `flutter:I`, which holds neither; now a run that ends without its line prints the exit reason Android recorded for its pid and logcat's `crash` buffer. 30 launches of 2 s runs 5 s apart afterwards (`mobs` and `orbit` alternated, the APK of `2f89a05`) did not crash once. |
| PF14 | regions of 4 | — (measured, not adopted) | `regionChunks` 4 (a worktree with the default changed) against 2, Galaxy S24, phone preset, three rounds alternated, right after the busy-CPU runs, so the battery at 38.1–39.1 °C on both sides: the columns compare, the absolute numbers are below the cool A/B's (`docs/perf/pf14_s24_phone_r4_regions{2,4}.jsonl`). Encode p50 **orbit 3.87 → 2.84 ms** (3.80–4.20 → 2.84–2.90), **fly 3.64 → 2.67**, mobs 4.72 → 4.20 (ranges overlap); UI p50 orbit 4.92 → 3.89, fly 4.73 → 3.74. The costs: **fly step p99 4.72 → 24.5 ms** (4.69–7.20 → 23.9–30.1: a chunk arriving rebuilds sixteen chunks' surfaces, three frames at 120 Hz), fly RSS 422 → 482 MB, and fps moves inside the noise (mobs 83.7 → 91.0, orbit 106 → 107, fly 110 → 102). A quarter of the encode is not worth a hitch at every streamed chunk: the default stays 2. |
| PF15 | greedy | `f60cd42` | `ChunkMesher` merges cube and liquid faces greedily (per direction and slice, as wide as a row allows along u, then whole rows along v), a merge allowed along a direction only where the corners' AO does not change along it, so the interpolation is the unit faces'; the key is block, sky and block light, the four AO corners and the lowered liquid top. The per-voxel colour variation left the vertex colour for the terrain shader (`VoxelTint`, the same 32-bit hash as `ChunkMesher.voxelTint`, of the cell a tenth of a block behind the face); the unlit `glow` surface keeps it baked and unmerged. **The example's `orbit:6` window** (a probe meshing the benchmark's 13 × 13 chunks, its count equal to the benchmark's `faces`): **faces 185,130 → 114,193** (solid 165,431 → 113,902, −31%; liquid 19,699 → 291), vertices 740,520 → 456,772; the mesh job 3.67 → 4.11 ms a chunk (JIT). Solid merges less than a flat world would: hills put AO on most edges, and the grass/dirt/stone and ore ids split the sides. A frame of `orbit:6` against the baked variation (release, Mac): 97.7% of the pixels identical, 99.7% within 2 levels, the rest (up to 37) on cells' edges, where multisampling now shades one cell's variation. |
| PF15 | A/B | this commit | Against `67725a5` (PF14's tree), three rounds alternated, 120 Hz. **Mac, release** (`docs/perf/pf15_mac120_ab_{67725a5,greedy}.jsonl`; the screen locked during the third round, so its locked lines are left out and the first two rounds judge, runs of both sides without overlap): **orbit:6 fps 101.1 → 109.3** (101.0–101.2 → 109.0–109.6), **orbit:12 70.5 → 85.9**, fly:6 118.6 → 120.8 (the display's rate), **fly:12 88.4 → 108.5**, mobs:6 102.7 → 110.0; frame p99 orbit:6 24.8 → 16.7; encode and UI p50 unchanged (0.31–0.72 ms: the draws are the same, only smaller); fly step p99 3.07 → 2.25 and fly:12 5.27 → 3.40 (less to upload a chunk); **RSS −8 to −20%** (orbit:12 686 → 548 MB). **Mac, GPU** (`--trace`, `docs/perf/pf15_mac120_trace_*.jsonl`): orbit:6 **9.78 ms a frame before** (97.7% busy; 9.99 in §Baseline at 120 Hz) **against 8.83 · 8.89 after** (95.6–96.1%), fly:6 7.51 · 7.48 after; the other traced runs of both sides failed (below), so the GPU number rests on one before run, and the release fps, GPU-bound, say the same (1000 / 101 = 9.9 ms, 1000 / 109 = 9.2). Still over the 8.3 ms a 120 Hz frame has at `orbit:6`. **Galaxy S24, phone preset** (`docs/perf/pf15_s24_phone_ab_{67725a5,greedy}.jsonl`, no run lost, battery 25.8–30.8 °C on both sides): **orbit:6 113.3 → 118.8 fps** (112.0–116.2 → 118.8–119.2, the display's rate), UI p99 15.0 → 8.0; **fly:6 step p99 5.43 → 2.91 ms** (4.82–5.82 → 2.70–4.03: PF14's region rebuild, half undone by smaller surfaces), UI p99 9.5 → 7.1; mobs:6 87.7 → 88.8 (82.6–99.0 and 85.5–94.2: noise); encode p50 unchanged on all three (the phone's encode is draws, not vertices); **RSS −43 to −57 MB**. |
| — | tooling | this commit | **`--trace` traces the tree's own profile build.** xctrace launches the app by its bundle id (`com.remottely.voxelGameExample`), and LaunchServices resolves it to any copy it registered or Spotlight indexed, **whatever path xctrace was handed** (the worktree's `.app` path launched this tree's `Profile`), and follows a registered copy through a rename. It also spawns a first process suspended (state `T`, orphaned to launchd) that never runs: one was left every traced run, so a failed trace of the release build left two. `runTraced` now hands xctrace the resolved executable, and while it records unregisters every other copy (`lsregister -u`; the LaunchServices dump and `mdfind` list them) and renames it to `….app.run_benchmark_aside`, which is no bundle, registers the tree's own (`lsregister -f`), refuses the run unless the trace's launched pid has that bundle's path (`xctrace export --toc`), then kills the app's processes that were not running before and moves the copies back; a copy found already aside stops the script. Checked with a traced A/B of `orbit:6` against a worktree at `67725a5` (the runner copied into it), three rounds alternated, unlocked (`docs/perf/trace_guard_mac1x_ab_{67725a5,0634891}.jsonl`): 6 of 6 traced runs of the right tree (`faces` 185,130 on the worktree's, 114,193 on this tree's), no process left, no recording left, every copy back. Before the fix the same calls from the worktree traced this tree's `Profile` 3 times in 4, each refused by the new check. The runs opened on the external 1080p display (`dpr` 1.0), so their GPU ms (5.87 → 5.67, 70% busy, 120 fps on both) do not compare with PF15's at 2.0. |
| PF13 | packed vertex | this commit | The three lit terrain surfaces draw in a **16-byte vertex** where `MeshGeometry` spent 72: `TerrainGeometry` (voxel_scene), a `Geometry` with its own layout and vertex shaders in the kit's bundle (`TerrainVertex`, and `TerrainDepthVertex` for shadows, prepass and mask), two streams of two `uint32` words unpacked with bit operations: the position in 1/256 m from the region's corner (the depth passes read it alone, 8 B where they read 12), then rgba8 (rgb as its square root), the normal biased by 128 and the two light levels. The glow surface stays in the engine's vertex (its baked colour passes 1.0). A debug run (asserts on) packed the whole `orbit:6` window without a failure; the pixels, release, `orbit` held at its start, cropped to the window: against the 72-B vertex 9.1% differ, **0.04% by more than 2 of 255** and 0.01% by more than 8, where two runs of the old build differ by 1.4% and 0.35%. A/B against `4d2e833`, three rounds alternated, unlocked, `dpr` 2.0 on every line. **Mac, traced** (`docs/perf/pf13_mac120_trace_{4d2e833,packed}.jsonl`): **GPU ms a frame at `orbit:6` 8.90 · 8.92 · 8.87 → 8.91 · 8.94 · 9.00, no change**, 96% busy on both: at `dpr` 2.0 the GPU pays for pixels, not vertex fetch. **Mac, release** (`docs/perf/pf13_mac120_ab_{4d2e833,packed}.jsonl`): `orbit:6` 109.0 → 109.2 fps; **`orbit:12` 84.0 → 93.7 fps** (runs 83.6–84.2 → 87.4–95.6), where 3.7× the faces are drawn; `fly:12` 112.0 → 114.3; **RSS −15% at radius 12** (503 → 426 MB `orbit:12`, 540 → 454 `fly:12`), 300 → 282 at `orbit:6`. **The cost: `fly:12` sim p99 2.33 → 4.12 ms** (runs 2.21–2.33 → 4.08–4.17), step p99 3.39 → 4.15, UI p99 3.97 → 5.70: packing on the UI thread when a region is rebuilt (every chunk of the region is repacked at every apply, sqrt and rounding per channel) costs more than copying floats did. **Galaxy S24, phone preset, in power-saving mode** (`low_power` 1, the display held at 60 Hz on both sides, so fps is capped and not a reference: `docs/perf/pf13_s24_phone_lowpower_ab_{4d2e833,packed}.jsonl`, battery 29–32 °C): encode p50 unchanged (`orbit:6` 4.28 → 4.32, `mobs:6` 6.35 → 6.50; it is draws × passes), GPU latency unchanged, fps 60 on both, **RSS −28 to −43 MB** (`orbit:6` 324 → 295, `fly:6` 366 → 323, `mobs:6` 366 → 338), `fly:6` step p99 4.85 → 4.74. |
| PF13 | pack once | this commit | **A chunk is packed once, when its mesh arrives, and a region's rebuild moves words.** `PackedSurface.of` packs one chunk's `MeshSurface` in its own frame; `PackedSurface.merge` joins a region's chunks, adding `ox·4096 | oz·4096 << 16` to the `x | z` word and copying `y` and the attribute words as they are; `VoxelChunkView` keeps the three lit surfaces packed (and no longer their floats) and the glow as floats. Bit-identical to the first packer: a whole number of metres is a whole number of 1/256 steps, `(p + ox)` is exact in double, and a region under 256 m never carries between the halves; a test packs random chunks (on and off the mesher's grid, 1 to 15 chunks a side) both ways and compares every word. Done in voxel_scene, not on the worker: the mesher's `MeshSurface` is the engine's API and its tests' and the minecraft example's, and the glow still needs the floats. A/B against `4b621de` (= `7a5dcf6`, PF13's first half, plus sound and docs), three rounds alternated, unlocked, `dpr` 2.0 on every line. **Mac, release** (`docs/perf/pf13b_mac120_ab_{4b621de,packonce}.jsonl`): **`fly:12` step p99 4.17 → 1.96 ms** (runs 4.12–4.45 → 1.89–2.65; 3.39 before PF13), **sim p99 3.77 → 1.90** (3.12–3.84 → 1.90–2.16), **UI p99 5.21 → 3.73** (5.19–5.27 → 3.20–3.94); fps unchanged (`orbit:6` 109.4 → 109.6, `orbit:12` 85.9 → 87.3, `fly:12` 113.5 → 113.2); **RSS −17% at radius 12** (451 → 375 MB `orbit:12`, 478 → 396 `fly:12`), 284 → 271 at `orbit:6`. **With the CPU held busy** (`yes` ×2, `fly:12` only, `docs/perf/pf13b_mac120_busy_ab_{4b621de,packonce}.jsonl`): step p99 4.03 → 2.37 (3.59–4.70 → 2.30–2.62), sim p99 3.35 → 2.08, UI p99 5.02 → 3.67. |
| PF13 | phone A/B | this commit | **Galaxy S24, phone preset, 120 Hz** (`low_power` 0, `refreshHz` 120 on every line), three sides in rounds A B C, C B A, A B C: `4d2e833` (before PF13), `4b621de` (its first half) and `340843c` (packed once), `docs/perf/pf13_s24_phone120_ab_{4d2e833,4b621de,packonce}.jsonl`, no run lost. The battery climbed from 30.5 to 36.5 °C across the 27 runs, so every side has a cool and a warm run and the spread is wide; medians of three. **`fly:6` step p99 3.80 → 3.96 → 2.68 ms** (runs 2.32–4.00 → 2.82–4.23 → 2.00–3.21), sim p99 2.92 → 2.74 → 2.16, UI p99 10.4 → 6.8 → 7.2; **RSS −53 to −72 MB over PF13** (`orbit:6` 344 → 311 → 291, `fly:6` 377 → 336 → 312, `mobs:6` 378 → 361 → 349). fps within the noise: `orbit:6` 112.2 → 118.3 → 117.2 (the one run at 95 is the last and warmest), `fly:6` 116.9 → 119.2 → 119.5, `mobs:6` 88 → 87 → 85 (79–108 across all); encode p50 unchanged (`orbit:6` 3.84 → 3.89 → 3.93, the first round lower on every side: the clock). On the phone PF13 buys memory and, packed once, a cheaper streaming step; the frame is still the UI thread's and the encode is draws × passes. |
| PF3 | design | this commit | §PF3, the design: what keeps the previous pose (`NodeBody`'s two), where `alpha` enters (`VoxelGame.frame`, `drawnTime`), the rigs' facing moved to their owner's node, the look drained once a frame and how that sits with rule 14, and the measurement PF3 needs first: no column saw how the view moves, and the benchmark posed its camera inside the step. |
| — | measurement | `0e19bc9` | `FrameStats.addView` and the report's `view` (`judder`, `stillFrames`; `--compare` shows both); the benchmark turns `orbit` and `mobs` through `InputMap.look`, once a frame by the frame's timestamp, with `playWithoutCapture` (a mouse), and moves `fly` by `game.time` (a walk). One run each on the Mac at 120 Hz, `dpr` 2.0, before PF3: **`orbit:6` judder 1.03, 577 still frames of ~1310; `fly:6` 1.00, 720 of ~1450**: the view moves in the 60 Hz steps, every other frame. fps, UI and step as before (`orbit:6` 109 fps, `fly:6` 121). |
| — | measurement | this commit | **The benchmark turns the view by `InputMap.turn`**, a steady rate `takeLook` integrates over its `dt` (a held stick), no longer by `look` fed from a persistent frame callback: that callback runs after paint, so each frame's turn reached the next frame and was weighed against that frame's `dt`. PF3's first probe showed it (`orbit:6` judder 0.46 with 1 still frame, the frames alternating 8.3 and 16.7 ms at ~105 fps, where `fly:6`, not turned, read 0.08). A mouse drained once a frame covers the frame's own interval, as the stick does. |

**Where the work stopped (2026-09-28, PF13 done).** Last commit: this one (`docs:`, PF13's
phone A/B at 120 Hz), over `340843c` (`voxel_scene:`, a chunk packed once, a region's rebuild
moving words) and `7a5dcf6` (the packed vertex). PF13 is done on both platforms: the Mac's
`fly:12` step p99 is 1.96 ms (3.39 before PF13, 4.17 after its first half), RSS −17% at
radius 12; the phone's `fly:6` step p99 2.68 and RSS −53 to −72 MB. The packing stays on the
UI thread (one chunk, once, when it arrives); moving it to the worker would change
voxel_engine's `MeshSurface` / `ChunkMeshResult`, which the engine's tests and the minecraft
example read, for what is now well under the old cost: not a step unless a trace asks.
Next step: **PF3, interpolation** (poses and the camera drawn between two steps with the
loop's `alpha`, the look applied per frame; pacing at >60 Hz), **on `opus 5.5:high`** (a
design across the loop, the player, the cameras and the rigs, judged by pacing on both
platforms; `opus 5.5:medium` once its design is written here). PF9 only after a trace shows
GC in the UI thread; then PF2 → PF4 → PF8 → PF10 → PF11 → PF12. Optional, one `tool:`
commit: `--compare` warns when the two sides differ in `dpr` or `refreshHz`, as it does for
`screenLocked`. After PF13 the Mac runs `orbit:6` at ~109 fps (the GPU
8.9 ms a frame at `dpr` 2.0, 96% busy: pixels, not vertices), `orbit:12` at ~94, `fly:12` at
~114; before it (after PF15)
the phone `orbit:6` and `fly:6` at the display's 119, `mobs:6` at 85–94 (encode p50 4.5 ms,
UI p50 6.2): on the phone the frame is the UI thread's and the encode is draws × passes
(PF12's outline, `KL-007`'s drops), not vertices. `KL-008` (the driver crash in the first two
seconds) did not come back in PF15's 25 phone launches; if a run dies, the runner prints the exit
reason and the crash log, and the tombstone is in `adb shell dumpsys dropbox --print
SYSTEM_TOMBSTONE`. **The phone's CPU clock is a closed lead:** four busy
loops holding the CPU up still run `mobs:6` at 92–99 fps, but an ADPF hint session from the
app does not buy that (the ADPF row in Progress), so it is not a step; Flutter 3.47.5 creates
none itself. The clock still colours every A/B on both platforms: a step reads slower when
the frame gets cheaper. Judge a step's cost with
the CPU held busy (`yes > /dev/null` ×2 on the Mac, four through `adb shell` on the phone)
when the A/B moves the UI thread. Judge a step by
`stepMs`, not `simMs`. An A/B of anything with creatures takes `d34acab` or later as its
before (the Wander fix changed the load). A search still spends its 400 nodes toward an
unreachable goal (0.3 ms on the Mac); no longer in the p99, so left. A phone run takes `--
--graphics=phone`, or `benchmark.dart` draws the desktop look. flutter_scene profiles
itself: `--dart-define=FLUTTER_SCENE_PROFILE=true` prints, every 120 frames, each render
pass's mean and max CPU time and the colour pass's draws and instances; a release build's
`print` reaches no output on the Mac, so a profiling build wraps `main` in a `runZoned`
whose `print` writes to `stdout` there and to the parent zone's print on Android (`_report`
there is `debugPrint`, which calls `print`: routing it to `_report` recurses and hangs).
KL-007: drops and projectiles still mesh a geometry each. Learned and not in the code: (1) the screen was
locked all night, so the first baseline is a preview; the reference was taken unlocked at
120 Hz the next day; (2) Instruments traces only a profile build, and `xctrace` leaves a
~1 GB raw recording per run in the user's temp dir (the script deletes it; by hand, delete
`$TMPDIR/instruments*.ktrace`); the disk had ~27 GB free; (3) `screencapture` works from
the VS Code terminal once VS Code has Screen Recording permission (granted 2026-09-25), and
`adb exec-out screencap -p` captures the phone; an app started from the terminal opens
behind it, `open -n <app> --args ...` brings it to the front; (4) the phone's adb serial is
`RQCY706J2YV` (Galaxy S24 Ultra), its screen timeout 10 minutes; (5) in zsh, `rm -f
dir/x*.jsonl` with no match aborts an `&&` chain, and a command in a variable (`A="adb -s
X"; $A ...`) is not split into words: use a function; (6) four `yes` on the phone heat
it from 34 to 40 °C in 18 runs and it throttles: hold the CPU busy for one scenario at a
time, and let the phone cool (under ~33 °C) before a run whose absolute numbers matter;
(7) a phone A/B needs no babysitting when a driver script calls the runner per side with
`--repeat 1` and launches again, `--no-build`, only the scenarios a failed call left; (8) a
`--trace` A/B across a worktree was unsafe (two "before" traces of PF15 ran the greedy
build; the line's `faces` gave it away) and (9) 28 of PF15's 33 traced runs ended in "no
composited frame in the traced window", xctrace launching the tree's **release** build by
its bundle id: both fixed in the runner (the tooling row after PF15's A/B), which now refuses
a trace of any other copy and kills what xctrace left; a worktree side runs the new runner
only if it is copied into it (`cp tool/run_benchmark.dart <worktree>/tool/`), since an older
commit carries the old one; a traced run that dies uncaught (Ctrl-C) leaves copies named
`….app.run_benchmark_aside`: the next traced run names them, move them back by hand; (10) a phone that
drops off USB hangs the runner at `adb logcat` with no error: a driver script that reports
each call's start time shows it as a call older than ~3 minutes. (11) with the
external 1080p display connected the benchmark's window opens on it at `dpr` 1.0 (a quarter
of the pixels): the GPU is no longer the wall there (`orbit:6` 5.7–5.9 ms, 70% busy, 120
fps), so PF13's Mac gate needs the window on the Retina display (`dpr` 2.0, as PF15's lines);
disconnect the external display or make the built-in the main one, and check `dpr` in every
line; (12) PF13 in flutter_scene 0.23 (read, nothing built): a `Geometry` subclass takes its
own vertex shader from the kit's bundle (`setVertexShader`) and its own layout
(`defaultVertexLayout`, attributes bound by name, vertex formats 32-bit only, so the packed
vertex is `uint32x2/3/4` unpacked with bit operations); the pipeline pairs the geometry's
vertex shader with the material's fragment (`scene_encoder.dart:522`), so `TerrainMaterial`
stands; the shader must output the standard varyings (`#include <material_vertex.glsl>`:
`v_position, v_normal, v_viewvector, v_texture_coords, v_texture_coords_1, v_color,
v_tangent`) and take `FrameInfo` and the 80-B instance record (`model_transform_0..3`,
`instance_color`) at the slot after the vertex streams; `bind()` must be written (templates:
`LineSegmentsGeometry`, the closest, whose varyings are the standard ones); shadow cascades,
depth prepass and selection mask use `depthOnlyVertex` when a geometry gives one (else its
full shader through `bind()`): give a position-only one; the velocity pass assumes a float
`position` but draws only moving nodes, which regions are not; `build_shaders.dart` lists
fragment shaders only, and a `"type": "vertex"` entry is what flutter_scene's own bundle
uses; today's surfaces are `MeshGeometry.fromArrays` (`voxel_chunk_view.dart:125`), six
streams of which uv0 and the tangent (24 B) are unused. (13) PF13 as built: a custom opaque
`Geometry` does reach the screen (the `LineSegmentsGeometry` note in `selection_outline.dart`
is about that class, not custom geometry); `setVertexStreams` and `bindGeometryBuffers` are
`@internal` to flutter_scene but needed for two streams (`terrain_geometry.dart` ignores the
lint); `uvec2` inputs compile with `--gles-language-version=300` and draw on Metal and
Vulkan, the GLES backend is untested; `packed` is a reserved word in GLSL. (14) the phone
can be in power-saving mode (`adb shell settings get global low_power` = 1): the display
drops to 60 Hz and every line says `refreshHz` 60; check it before a phone A/B. (15) the
pixel diff: `open -n <app> --args --scenario=orbit --radius=6 --seconds=100000 --window=1600x900`
holds the camera still, `screencapture -x` at 14 s, crop the window (`(140, 220, 3320, 2000)`
on the Retina), compare two runs of the same build too, for the noise. (16) at 120 Hz with no busy loop the phone still warms
~0.7 °C a call of three scenarios (30.5 → 36.5 °C over PF13's nine calls): a driver script
that waits for the battery under ~33 °C before each call keeps a phone A/B's absolute
numbers; the Mac's `orbit:12` read 84–95 fps on the same build across days, so compare it
only within one A/B.
