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

**A host with peers** (PF11) is any scenario with two flags after `--`: `--peers=N` hosts
the game on a loopback port once the window fills and joins N scripted peers from an isolate
of their own (each drains what it receives and sends its pose 20 times a second; the
recording waits for all N), and `--edits=N` edits N cells in one step every second of the
recording (a cube of leaves two chunks east of the spawn, set and cleared in turn; not with
`fly`). The line gains `peers`, `edits` and `bursts`. The host's work runs inside the step,
so `stepMs` holds it, the bursts at its p99 and max.

**The selection outline** (PF12) is drawn only while the crosshair rests on something, which
no scenario's look does from its height: `--aim` after `--` gives the player a reach of 160 m,
so the look meets the terrain (across valleys and water) the whole turn and the outline is
shown by the game's own aim, where the terrain puts it. The line gains `aimed`, the share of
the recorded steps whose outline was shown (1.0 in `orbit:6`).

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
taken at the same rate and ratio (`--compare` warns when the sides differ in either). With the external 1080p display connected the window opens
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

**The final comparison (PF17) is an A/B in one sitting** (taken: §The final measurement), unlocked, which makes the locked
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
Mac's, and a longer cooldown is part of the method there. Before each run the script waits
for the battery to be under `--max-temp`, **36 °C by default**: at 120 Hz the phone stays
over 33 °C for minutes between runs, so a lower bar only makes every call wait; sides are
compared at similar temperatures inside 36, not cooled further. A run with the CPU held busy
waits before the busy loops start and passes `--max-temp 99`, or it would wait forever. The keyguard counts as a locked
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

## The final measurement (PF17)

Taken 2026-09-29, 13:20–14:35, in one sitting: the Mac unlocked and left alone, its
built-in display at 120 Hz (`dpr` 2.0 on every line, no external display), on AC; the phone
on USB, `low_power` 0, unlocked, 120 Hz on every line. Every side a detached worktree (the
tip too, so another session's dirty file stays out of `commit`), each build warmed by a
discarded 3 s run, rounds alternated with the order swapped each round, **no run lost** on
either platform. Medians of 3, the runs' range in brackets.

**How the befores were run.** The Mac's before is `67da3ac`, the harness before any
optimisation. The phone's is `797de1d`, the first commit whose example runs on Android: its
default look is the desktop one (PF1's phone preset exists there but `benchmark.dart` takes it
only from `--graphics=phone`), so it gives both the phone before any step and PF1 alone. Each
worktree ran the tip's `tool/run_benchmark.dart` (copied in, so the lock check, the
temperature wait and the trace guard are the tip's), with two local edits that are not
committed: a line without `mode` is accepted (the old `benchmark.dart` does not print it),
and its `gpuMs` is written as `gpuLatencyMs`, as the committed lines were migrated. The old
shader bundle boots on Flutter 3.47.5 (it rebuilt byte for byte the same on that version, ledger KL-005).

**Mac, release** (`docs/perf/pf17_mac120_ab_{67da3ac,b49ec54}.jsonl`), no range overlapping:

| run | fps before | fps after | frame p99 ms | UI p50 ms | UI p99 ms | encode p50 ms | sim p99 ms | fill ms | RSS MB |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| orbit:6 | 100.4 [100.3–100.6] | **111.3** [110.8–111.4] | 22.9 → 16.7 | 0.71 → 0.33 | 1.89 → 2.12 | 0.61 → 0.30 | 0.03 → 0.13 | 385 → 279 | 298 → 253 |
| orbit:12 | 77.2 [76.8–77.4] | **96.6** [95.9–98.5] | 33.3 → 24.0 | 2.02 → 0.60 | 6.70 → 1.47 | 1.87 → 0.57 | 0.09 → 0.03 | 1047 → 658 | 501 → 352 |
| fly:6 | 118.8 [118.6–118.8] | **120.7** [120.5–121.8] | 16.7 → 8.34 | 0.67 → 0.83 | 2.16 → 2.73 | 0.57 → 0.69 | 0.77 → 1.47 | 388 → 272 | 310 → 268 |
| fly:12 | 97.8 [89.6–97.9] | **118.1** [116.8–118.1] | 25.0 → 16.7 | 1.79 → 0.66 | 6.19 → 4.00 | 1.68 → 0.65 | 1.98 → 1.85 | 1040 → 658 | 537 → 380 |
| mobs:6 | 46.8 [46.8–47.8] | **112.8** [112.1–113.3] | 91.7 → 16.9 | 8.92 → 1.12 | 74.7 → 4.49 | 3.30 → 0.76 | 71.3 → 2.06 | 380 → 290 | 357 → 258 |

Hitches 283 → 171 (`orbit:6`), 500 → 348, 30 → 1 (`fly:6`), 290 → 96, 229 → 169. The view
moves by the time that passed after PF3: judder 0.00 turning and 0.05 flying, no still frame
turning, where the harness moved it every other frame (judder 1.03, 577 still frames of
~1310 at `orbit:6`, the measurement row of `0e19bc9`; the before's line has no `view`).

**Mac, the GPU** (`--trace`, profile, `docs/perf/pf17_mac120_trace_{67da3ac,b49ec54}.jsonl`;
18 of 18 traced runs of the right tree, `faces` 185,130 against 114,193):

| run | GPU ms a frame before | after | busy % before → after | fps (profile) |
|:--|--:|--:|--:|--:|
| orbit:6 | 10.11 [10.03–10.12] | **8.81** [8.78–8.81] | 99.1 → 96.4 | 97.8 → 109.5 |
| orbit:12 | 13.47 [13.33–13.49] | **10.66** [10.46–10.77] | 100 → 100 | 74.0 → 93.5 |
| fly:6 | 8.31 [8.28–8.35] | **7.62** [7.60–7.62] | 97.6 → 91.3 | 117.2 → 120.2 |

**Galaxy S24 Ultra, 120 Hz** (`docs/perf/pf17_s24_phone120_ab_{797de1d_desktop,797de1d_phone,b49ec54_phone}.jsonl`;
three sides in rounds A B C, C B A, A B C; every run waited for the battery under 36 °C and
started at 34.0–35.9):

| run | fps before (desktop look) | fps PF1 alone (phone preset) | fps after (phone preset) | UI p50 ms | encode p50 ms | sim p99 ms | fill ms | RSS MB |
|:--|--:|--:|--:|--:|--:|--:|--:|--:|
| orbit:6 | 36.3 [32.1–37.2] | 69.3 [66.0–84.9] | **118.2** [117.6–118.6] | 22.1 → 8.4 → 4.5 | 20.9 → 7.4 → 4.0 | 0.20 → 0.13 → 0.12 | 893 → 735 → 567 | 368 → 377 → 268 |
| orbit:12 | 20.7 [17.6–23.4] | 59.8 [53.6–60.0] | **79.9** [72.9–80.1] | 40.3 → 12.0 → 7.5 | 39.1 → 11.3 → 7.0 | 0.20 → 0.10 → 0.15 | 2709 → 2017 → 1549 | 639 → 640 → 377 |
| fly:6 | 37.5 [31.7–40.0] | 109.0 [101.9–114.8] | **119.9** [119.6–120.2] | 20.6 → 5.5 → 4.3 | 19.1 → 4.7 → 3.7 | 4.99 → 1.59 → 1.48 | 845 → 735 → 575 | 384 → 382 → 276 |
| mobs:6 | 19.5 [19.0–20.0] | 26.1 [26.0–26.6] | **93.5** [87.9–96.3] | 31.0 → 15.0 → 5.9 | 9.9 → 7.4 → 4.8 | 85.1 → 86.0 → 7.5 | 886 → 748 → 566 | 483 → 459 → 269 |

Frame p99 `orbit:6` 66.6 → 25.0 → 16.7 ms, `mobs:6` 108 → 92 → 25; hitches `orbit:6`
414 → 571 → 33, `fly:6` 432 → 145 → 12.

**What it says.**

- **Mac: +11% to +141% fps, every scenario but `fly:6` held by the display, not by the
  kit.** `mobs:6` 47 → 113 (PF5, PF6, PF7: the creatures' CPU wall is gone, sim p99 71 → 2
  ms), radius 12 +21–25% (PF13, PF15: fewer, smaller vertices), `orbit:6` +11% (PF15's
  greedy faces). The UI thread spends 0.3–1.1 ms at p50 of the 8.3 a frame has, and memory
  is 15–30% lower. The GPU's cost a frame fell 13% at `orbit:6` (10.1 → 8.8 ms), 21% at
  `orbit:12` (13.5 → 10.7) and 8% flying.
- **Phone: 2.5–4.8× fps over the harness, 1.3–3.6× over PF1 alone.** `orbit:6` and `fly:6`
  reach the display's 120, `mobs:6` 19 → 94, `orbit:12` 21 → 80. The UI thread went from
  20–40 ms at p50 to 4.3–7.5; memory is 28–44% lower (radius 12 640 → 377 MB).
- **PF1 alone read lower than in §Baseline at 120 Hz** (`orbit:6` 69 against 99, the desktop
  look 36 against 36): that sitting started cool (29.9 °C) and this one at the 36 °C base
  throughout, and a build whose frame is the UI thread's (8.4 ms at p50, over the 8.3 budget)
  loses the most when the clock drops. The tip, 4.5 ms at p50, holds 118 at the same heat.
- **The ceiling on the Mac is the GPU paying for pixels.** At `dpr` 2.0 `orbit:6` costs
  8.8 ms a frame, 96% busy, against 8.3: the last 9 fps to 120 are fill, which PF13 showed
  vertices do not move (8.9 before and after it); at `dpr` 1.0 the same scene traces 5.7–5.9
  ms and holds 120 (PF15's note). Radius 12 is 100% busy at 10.7 ms. What is left is the
  lit shader × MSAA × four cascades on a Retina surface: `GraphicsSpec` (render scale,
  anti-aliasing, shadows) trades it, the kit cannot draw it cheaper without culling hidden
  terrain, for which Flutter GPU has no compute and no indirect draws (the investigation of 2026-09-24).
- **The ceiling on the phone is flutter_scene's encode on the UI thread.** At radius 6 the
  frame fits (UI p50 4.5 ms); at radius 12 the encode alone is 7.0 of the 7.5 ms the UI
  thread spends at p50, and the frame rate stops at 80: draws × passes, recorded in Dart
  inside paint, at ~31 µs a draw on this phone (PF14's row). The kit has already cut the
  draws it owns (PF7, PF12, PF14); what is left is flutter_scene's per-draw cost and its
  shadow re-render on the sun's step, both in PF16's issue (bdero/flutter_scene#435).
  `mobs:6` at 94 carries a step p99 of 7.6–11.7 ms, the searches `Mob.searchesPerStep`
  still allows in one step (the Mac, 1.1–2.4 ms).

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
| PF9 | Garbage, in the order PF8's trace weighed it: the workers' per-job allocations (the generator's and the mesher's lists, each generation's fresh volume), the UI isolate's per-frame garbage and what it allocates straight into old space, then the per-step garbage (`VoxelBody`, raycasts, rig parts, list copies) | voxel_engine, voxel_game, voxel_scene | the collections inside `fly`'s frames (the landed frames' tail), UI p99, sim p99 |
| PF10 | Audio: recipes synthesised off the UI isolate | sound_recipes, voxel_game | UI p99 at start; fill ms (`SoundBank.init` holds the UI isolate for the fill's first ~100 ms on the Mac, 250–400 on the phone: PF8's probe) |
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

### PF2, the design (2026-09-28)

**What the row asked for, and what is left of it.** Two of PF2's three items landed with
other steps: PF14's `MergedSurface` and PF13's `PackedSurface` merge into 16-bit indices
while a region's vertices fit, and take the region's bounds (its heights) during the copy.
What is left is where the streaming spends the UI thread, and when.

**Where it goes** (a probe, not committed: stopwatches in `ChunkStreamer.updateAround` and
`update`, in `VoxelChunkView.apply` and `_rebuild` split into packing, merging and the GPU
upload; release, Mac at 120 Hz, `dpr` 2.0, 12 s of `fly` on `72e53e9`). **`fly:12`**: 78 ms
of streaming in 12 s (0.6% of the UI thread), in 52 frames; 300 applies, 250 removals, 485
region rebuilds. Applying is **40% packing** (31 ms), 34% merging (27), 19% the upload (15);
merge and upload together 16 ns a vertex. The work comes in **bursts**: the mesh jobs of the
column that enters the window finish together, so one frame applies up to 15 chunks (4.6
ms, the run's slowest UI frames), and **once a second the column that leaves is removed in
one frame**, 25 chunks inside `updateAround`, outside any budget (1.6–2.2 ms). Each apply
and each removal rebuilds its region at once: a region is rebuilt with 1, 2, 3 then 4
chunks as they land (143, 138, 132 and 72 of the 485 rebuilds), twice when a leaving column
takes two of its chunks, and rebuilt with its last chunk only to be emptied the next
second. `ChunkStreamer.frameBudgetUsec` (7 ms, checked after each apply) never stopped a
burst. `fly:6`: the same shape, 13 chunks a burst, 44 ms in 12 s. **On the phone** these
bursts are the hitches: PF3's `fly:6` at 120 Hz has 16–18 hitches in 12 s, UI max 15–18 ms
and sim max 6–7 ms, about one per burst (12 columns in, ~12 out), where the Mac, four times
faster, absorbs them (UI max 4–6 ms). (The phone A/B disproved this: see PF2's rows in Progress.)

**A region is rebuilt once a frame, inside a budget, nearest first.** `VoxelChunkView.apply`
keeps the chunk's `ChunkMeshResult` surfaces and marks its region dirty; `remove` drops them
and marks it dirty; neither builds anything. `VoxelChunkView.rebuild(ChunkPos near,
{budgetUsec})`, once a frame from `GameWorld.update` after the streamer's, rebuilds the dirty
regions nearest `near` first (the focus chunk: an edit beside the player before the window's
edge, a leaving column last), each once however many of its chunks changed, and a region
left with no chunk drops its node without counting. The budget is checked **before** each
region: its cost is predicted from its vertices, `pack × the chunks not packed yet +
merge × all of them`, two rates in µs a vertex measured on the rebuilds already done (a
running mean), and a region that would pass the budget waits for the next frame; the first
region of a frame is always built, so the view keeps up whatever it costs.
`rebuildBudgetUsec` is **2 ms**, a quarter of a 120 Hz frame: the phone's UI p50 at `fly:6`
is 4.6 ms of the 8.3, and a burst spread over frames delays a chunk by a few frames at the
fog's edge, where the window loads and unloads. The throughput it leaves is far above what
flying asks: `fly:12` needs ~25 region rebuilds a second, and 2 ms × 120 frames is 240 ms
of them a second. **Packing moves into the rebuild**: a chunk is packed the first time a
rebuild reads it and kept packed, still once, so all of the view's UI-thread work is inside
the budget, and a remesh that lands before its region is rebuilt is never packed.
`pendingRegions` counts what waits; `GameWorld.isIdle` waits for it too.

**What does not change.** `ChunkStreamer` hands every finished mesh and every removal to its
sink as it does; `frameBudgetUsec` stays for the sinks that build in `apply` (the minecraft
example's reads it), and with this view an apply is bookkeeping. The mesher, the worker's
messages and `MeshSurface` stay as they are.

**What is left for after the A/B.** Packing on the worker (the words and the bounds made
where the mesh is, the other half of the row's last item) would take the 40% off the UI
thread instead of spreading it, but the packed vertex is voxel_scene's and the worker is
voxel_engine's: it needs a way for a sink to hand the worker a sendable packer. It is done
only if the A/B still shows streaming in `fly`'s UI p99 or hitches.

**Judged by** hitches, UI p99 and max, sim p99 and max, on `fly:6` on the phone and `fly:12`
(`fly:6` too) on the Mac, and `fillMs` (the window's first fill goes through the budget too);
`stepMs` holds the streaming only in frames that ran a step, half of them at 120 Hz. A/B
against `72e53e9`. Tests (voxel_scene, no GPU: empty surfaces): apply and remove build
nothing until `rebuild`; four applies to one region build it once; a zero budget builds
one region a call; the nearest region goes first; a region whose chunks all left is dropped
in the same call.

### PF4, the design (2026-09-28)

**What is wrong today.** `VoxelGameWidget._tick` bumps a `ValueNotifier<int>` every frame
and a `ValueListenableBuilder` under it calls the `HudBuilder` again, so `DefaultHud` is
built, laid out and painted from scratch 120 times a second: a `Stack` of about sixty
widgets (ten hearts, nine hotbar slots with their counts, the held item's name, the
crosshair, the "click to play" line, each text with a blurred shadow), of which nothing
changes in `orbit`, `fly` or `mobs`. And it would be painted every frame even if it were
not rebuilt: `SceneView` paints through a `CustomPaint` whose `repaint` listenable fires
every tick, a `CustomPaint` is not a repaint boundary, so the nearest boundary above it (the
route's) repaints everything under it, the HUD included. The typedef's own doc says it:
"rebuilt every frame, so keep it light". Only `DefaultHud` uses `HudBuilder` (the minecraft
example builds its own HUD outside the kit).

**The HUD is built once, and each piece watches what it shows.** `HudSelector<T>` (new,
`lib/src/ui/`): a widget given a `Listenable` that ticks once a frame, a `select` that reads
a value from the game, and a `builder` of that value; it runs `select` on every tick and
rebuilds only when the value is not `==` to the last one. A value is a record of primitives
(`(String, int, bool)` for a slot), so equality is structural and nothing is hashed.
`VoxelGame.frames` (a `ValueListenable<int>`, the frames drawn so far) is that tick: it
moves at the end of `VoxelGame.frame`, where the widget's own counter moved, so a HUD needs
only the game, and a headless game ticks it too. `DefaultHud` becomes a static tree of
selectors, one per thing that changes: the hurt flash, the mining bar, the hearts (`hp`),
each hotbar slot (its id, count and whether it is selected: selecting a slot rebuilds two),
the held item's name, "click to play" (`input.wantCapture`) and "You died". While nothing
changes a frame costs nine small record reads and no build.

**`HudBuilder` is called when the widget builds, no longer every frame** (when the game
starts and when a screen opens or closes). That is a break of voxel_game's API, under
`## Unreleased` with PF2's: a custom HUD that read the game in its build without a selector
would freeze, so the typedef's doc says to watch through `HudSelector` or `game.frames`.
The HUD sits behind a `RepaintBoundary`, so the scene's paint every frame reuses the HUD's
layer and the HUD repaints only when a selector rebuilds. The scene keeps no boundary of its
own: what repaints with it is the widget's `Stack` and listeners, which paint nothing.

**What does not change.** What the HUD shows and where; `InventoryScreen` (built only
while open, and rebuilt by its inventory's listeners); the game's frame and step. The
GPU still draws the HUD every frame (Impeller keeps no raster cache, so the blurred shadows
cost what they cost, ~3% of the Mac's GPU at `orbit:6`, §Baseline at 120 Hz): PF4 is UI
thread, not GPU.

**Judged by** UI p50 and p99 on `orbit:6`, `fly:6` and `mobs:6`, the phone above all (its
frame is the UI thread's: UI p50 ~4.9 ms at `orbit:6`, ~3.9 of it the encode, so the HUD
and the step share the other ~1), with the CPU held busy for one scenario (the clock slows
when a frame gets cheaper, PF7). A/B against `2b7a1d6` on the Mac and the phone. Tests:
`HudSelector` builds once for ticks that select the same value and again when it changes;
`VoxelGame.frames` moves once a frame.

### PF8, the design (2026-09-28)

**What is wrong today** (the PF8 probe row in Progress). `ChunkWorkerPool.defaultWorkers` is
one isolate per core but one, 11 on the M2 Pro (8 performance and 4 efficiency cores) and 7
on the Galaxy S24 (one prime, five performance, two efficiency), and neither machine fills
faster past ~8 and ~4: the extra workers only slow the others and hold ~4 MB of mesher
buffers each. `ChunkStreamer._dispatch` runs once a frame, inside `update`, so a mesh whose
ring's last generation lands waits for the next frame (p50 3 ms, p99 ~85 ms on the Mac, whose
fill presents a frame every ~20 ms), and the nine volumes it sends are copied by
`SendPort.send` inside that frame: 288 KB, p99 0.9–1.6 ms on the phone, where the frames in
which meshes land read p99 7.3–8.3 ms of work against 5.8 for the others. Isolates of one
group share one heap, so that copy is also 288 KB of new garbage on the UI isolate per mesh
(~48 MB over `orbit:6`'s 169 meshes, ~3.7 MB a second in `fly:6`), and the VM collects the
group's heap with every isolate in it stopped: whether the p99 is the copy or a collection
(which the workers' own allocations trigger too) the probe could not say.

**(1) The pool is two thirds of the cores.** `defaultWorkers` becomes
`max(1, Platform.numberOfProcessors * 2 ~/ 3)`: 8 on the Mac (its performance cores), 5 on
the S24, 2 on a four-core phone. The probe's fill at those sizes is within 1% of today's on
the phone (735 against 728 ms; a mesh job cost 10.6 ms at 4 workers and 15.8 at 7) and 5%
on the Mac (402 against 383), which (3) is expected to win back; the freed cores go to the UI and raster
threads, and each worker less is its isolate and mesher buffers less in RSS.
`ChunkWorkerPool(workers:)` still overrides it. No API moves.

**(2) The ring without a copy: volumes in native memory, the API unchanged.** The pool's
`generate` returns its volume in native memory: the worker copies the generator's list into
a block it allocates (`malloc` from `package:ffi`, a new dependency of voxel_engine, pure
Dart; `dart:ffi` alone has no allocator on Windows) and replies with its address; the UI
isolate wraps it as a `Uint8List` (`Pointer.asTypedList` with `malloc.nativeFree` as its
finalizer, so the memory lives as long as the list) and records the address in a static
`Expando<int>` keyed by that list. `mesh` sends the nine addresses (0 for a missing
neighbour), the worker reads them through `asTypedList` without a finalizer, and the pool
holds the ring's lists by job id until the reply lands or the worker exits, so no volume is
freed while a worker reads it; `dispose` keeps them until each killed worker's exit arrives
(`kill` stops a worker at its next check, not at once). So `ChunkJobs.mesh` keeps its
`List<Uint8List?>` and no game changes: the streamer, its edits and its queries read the same
lists, and a volume the pool did not allocate (none of the streamer's: every one comes from
its jobs' `generate`) fails the job with an `ArgumentError` (rule 5). The expando is per
isolate, not per pool, so a pool that replaces another (`GameWorld.start` again) meshes the
volumes the first one generated. An edit written while a worker reads the volume is a byte,
read whole, old or new; the job saw either the old blocks, which the copy guaranteed, or
the new ones, and an edit that matters to the chunk being meshed already queues it in
`_remeshAgain`, whose next job reads it after a `send`, which orders it.

**(3) A mesh goes out when its ring's last generation lands.** In the generation's `then`,
after `_putChunk`, the streamer dispatches the mesh of each of the nine chunks whose ring
holds the one that landed, if it is pending, not in flight or waiting for the sink, its
ring complete, and `maxInflight` allows: never the whole pending walk, which would dispatch
new generations too, and a headless world (`_LocalJobs` answers by `Future.value`, so a
`then` runs in the same call's microtasks) would then load its whole window in one
`update`. A mesh landing dispatches nothing; `update` still dispatches what is left (the
capped, the remeshes). The probe's prototype of it took the Mac's fill 387 → 350 ms
(`fly:12` 1000 → 925). It also moves most of the rings' sends out of the frame, into the
message handler between frames, where `simMs` and the UI thread's `buildDuration` no longer
see them but a late frame still would (hitches, frame p99).

**Built in the order (1), (3), (2).** (1) and (3) are a line each and their evidence is the
fill; (2) is the one that crosses the isolate boundary in raw memory, and (3) takes part of
its cost out of the frame first. So (2) is built only if, after (1) and (3), the phone's
frames in which meshes land still read over the others by more than the spread (the probe
re-applied on that tree), and it is kept only if its A/B lowers them: if they stay, the
tail is the group's collections, not the copy, and it belongs to PF9. One commit each.

**Judged by** fill ms (`orbit:6`, `fly:6`, and `fly:12` on the Mac), UI p99, sim p99 and
max, hitches and frame p99 in `fly` (the sends (3) moves between frames), RSS for (1), and,
for (2), the landed frames' p99 and the send's from the probe. One A/B for (1) and (3) with
three sides in rounds A B C, C B A, A B C: `3cfa2b9`, (1), (1) + (3), on the Mac (`orbit:6`,
`fly:6`, `fly:12`) and the phone (`orbit:6`, `fly:6`), and the busy-CPU run on both
(`fly:6`, `yes` ×2 on the Mac, ×4 on the phone). Tests: the default is two thirds of the
cores; a landed generation dispatches the meshes its ring completes and no generation, and
a headless window still needs more than one `update` to fill; (2)'s: a pool's volumes are
native and its mesh equals the local mesher's, a volume from elsewhere fails the job, a
ring outlives a `dispose` until its worker exits.

**What does not change.** `ChunkJobs`, `ChunkMeshResult` (the reply's surfaces and light
volumes already cross as `TransferableTypedData`, materialized without a copy), the
streamer's cap (24 in flight) and the pool's queue (the probe's `--depth` bought nothing),
and the ~100 ms (Mac) to 250–400 ms (phone) `SoundBank.init` holds the UI isolate at the
start of every fill, which is PF10's.

### PF11, the design (2026-09-29)

**What is wrong today.** `NetHost.broadcast` hands the message to each peer's
`NetConnection.send`, which runs `jsonEncode` and `socket.writeln` for that peer: the same
message is encoded once per peer, and `writeln` is two writes (the line, then `\n`), each
one `add` to the socket's sink. `HostSession` broadcasts one `set` for every block edited,
from `GameWorld`'s listener, as the edit happens: an explosion of radius 3 edits ~120 cells
in one step, so ~120 messages × peers, and the client decodes and applies each one on its
own. And 20 times a second the host broadcasts its `state` (every player and creature,
5.8 KB with the benchmark's 40 creatures), again encoded once per peer.

**The cost exists: a probe, before the design.** A standalone AOT program (outside the
tree; the host's loop on one isolate, N peers on another draining loopback sockets, the
message shapes of `sessions.dart`) timed each shape on the Mac, p50 over 200–400 rounds:

| shape | 1 peer | 4 peers | 8 peers |
|:--|--:|--:|--:|
| `state`, 40 creatures, encoded per peer (today) | 94 µs | 369 µs | 797 µs |
| `state`, encoded once, one UTF-8 buffer added to every socket | 93 µs | 106 µs | 122 µs |
| 113 edits in one step, a `set` each, encoded per peer (today) | 443 µs | 1707 µs (p99 3.0 ms) | 3338 µs (p99 5.9 ms) |
| 113 edits in one step, one message, one buffer | 31 µs | 37 µs | 50 µs |

A peer costs the host ~95 µs a `state` today and ~4 µs once the line is shared: ~80 µs is
the encode, and most of the rest is the second write. The edits cost ~3.7 µs an edit a peer,
nearly all of it the write, not the encode. On the phone, where Dart runs the step ~2.4×
slower than on the Mac (PF7's steps), an explosion with 4 peers holds the step for 4–7 ms of
the 8.3 a frame has at 120 Hz. So the step does two things wrong, and PF11 fixes both.

**(1) A broadcast is encoded once** (voxel_engine). `EncodedMessage` (new, `connection.dart`),
an extension type over the message's JSON line in UTF-8 with its newline, is made once;
`NetConnection.sendEncoded` adds it to the socket, one write, and every peer's sink holds
the same bytes (a sink does not modify what it is given). `NetHost.broadcast` encodes once
and sends it to every peer; `NetConnection.send` becomes `sendEncoded(EncodedMessage(m))`,
so a single send is one write too. No API breaks: `EncodedMessage` and `sendEncoded` are new.

**(2) Edits go out once a step, together** (voxel_game). `HostSession` and `ClientSession`
keep the step's edits in a flat `List<int>` (x, y, z, id per edit) and send them as one
`edits` message when the session ticks, which becomes the **last thing the step does**
(after the flow, the circuits, the spawner, the game's systems and `onTick`, before the
prune), so an edit of this step, whoever made it, leaves in this step. Every step with an
edit sends one message, whatever the 20 Hz clock says; the `state` keeps its 20 Hz. The
host's edits arrive from a client between frames, `storeEdit`, and leave with the next
step's, to every peer, the sender included, as today. The receiver applies an `edits`
message in order, so a cell edited twice in one step ends as the last edit said. The wire
changes (`set` is gone): a host and a client of different versions cannot talk, which they
already could not rely on (the protocol has no version); the CHANGELOG says so.

**How a host with peers is measured.** No scenario loads a host, so `benchmark.dart` gets
two flags (committed, in the measurement commit that is the A/B's before):
`--peers=N` hosts the game on a free loopback port once the window fills, and starts N
scripted peers on an isolate of their own (each joins with `joinHost`, drains what it
receives, and sends its pose 20 times a second, walking a circle around the spawn); the
recording starts only when the host counts N remote players, or the run fails.
`--edits=N` edits N cells of a cube near the spawn in one step every second of the
recording, stone and air in turn, so every edit is a change. The host's work is inside the
step (the listener and the session's tick run in it), so `stepMs` holds it: 12 burst steps
among ~720 put the bursts at step p99 and max. Peers on the same machine take cores, not
the UI thread; loopback writes cost what a network socket's do on the sender's side.

**Judged by** step p99 and max, frame p99 and hitches on `orbit:6 -- --peers=4 --edits=125`
(the bursts; `orbit` so no search colours the step), and step p50, UI p50 on
`mobs:6 -- --peers=4` (the `state` at 5.8 KB: ~0.26 ms saved every third step on the Mac,
so it may sit inside the spread; the probe above is its number). A/B in three sides,
rounds A B C, C B A, A B C: the measurement commit, (1), (1) + (2), on the Mac and the phone.
Tests: voxel_engine's, a broadcast reaches every peer and a large one arrives whole (the
existing test, with two clients); voxel_game's, the client and host test keeps passing
over `edits`, and a step's burst of edits reaches the client as one message whose cells all
land, a cell edited twice ending as the last edit.

**What does not change.** The `hello` (one per join), `pose`, `hit`, `hurt` and `bye`;
the `state`'s 20 Hz and its content; TCP with `tcpNoDelay`; who is authoritative.

### PF12, the design (2026-09-29)

**What is wrong today.** `SelectionOutline` draws the twelve edges of the aimed box as twelve
nodes, each a `MirroredCamera.primitiveNode` (a node holding a mirrored child) with a
`CuboidGeometry` of its own. flutter_scene batches opaque draws that share a pipeline, a
geometry and a material into one instanced call (`opaqueBatchEnd`, `render/instance_batching.dart`,
after the sort by pipeline, material and geometry), so twelve geometries are twelve draws, and
the 24 nodes are visited by the cull every frame. The mining crack (`FirstPersonView`, voxel_game)
is built the same way and its stages add up: 12, 24, 42 and 60 sticks, a geometry each, all drawn
while a block is mined, the outline's twelve on top.

**The cost exists: a probe, before the design** (note 32). A release build of `d92bcc6` with
flutter_scene's own profile (`--dart-define=FLUTTER_SCENE_PROFILE=true`, `print` routed to
`stdout` on the Mac), `orbit:6` with and without `--aim` alternated, three runs each, the medians
of the last ten 120-frame samples of each run (the recording):

| `orbit:6` | colour draws | colour encode | cull | scene pass | encode p50 | UI p50 | fps |
|:--|--:|--:|--:|--:|--:|--:|--:|
| **Mac**, `dpr` 2.0, no outline | 38.5 | 156–161 µs | 25 µs | 213–219 µs | 0.30 ms | 0.33–0.34 ms | 111–112 |
| **Mac**, outline shown (`--aim`) | 50.5 | 190–192 | 34–36 | 258–263 | 0.34–0.35 | 0.37–0.39 | 111–113 |
| **Galaxy S24**, phone preset, 31–33 °C, no outline | 40.5 | 1817–1842 | 161–166 | 2526–2575 | 3.9–4.1 | 4.4–4.6 | 119 |
| **Galaxy S24**, outline shown | 52.5–53 | 2053–2200 | 213–223 | 2802–2986 | 4.3–4.4 | 4.8–5.0 | 117–118 |

The twelve draws are ~30% more draws than the whole terrain's (PF14's regions): they cost
~35 µs of the colour pass and ~10 µs of cull on the Mac, and **~0.3 ms and ~55 µs on the phone
(~25 µs a draw), ~0.35 ms of the encode's median and ~1.5 fps** at 120 Hz. The shadow pass does
not move (the sticks cast none).

**One shared cube is half of it.** Sharing one unit `CuboidGeometry` among the twelve sticks
(the thickness moved into each node's scale) does batch them, a probe on the Mac says: 39.5 draws,
51 instances, the colour encode 173–176 µs, but the cull stays at 34–36 (the 24 nodes) and the
instances are packed and bound every frame (~6 µs): about half the cost is left.

**So the outline is one mesh** (voxel_scene). `BoxMesh` (new, `box_mesh.dart`) turns a list of
boxes (`Aabb3`) into flat arrays, four vertices and six indices a face, wound as the chunk mesher
winds (clockwise from the normal side, drawn through `MirroredCamera` with no mirrored node), and
into a `MeshGeometry`. `SelectionOutline` keeps one node: its mesh is the twelve sticks of the
box's span, built the first time that span is shown and kept by span (the shapes a game aims at
are few: a full cell, a slab, a torch's post, each creature's collider), and `show` moves the
node to the box's corner and swaps the mesh only when the span changes; a creature aimed every
frame costs a position. One node, one draw, nothing packed. `SelectionOutline.stickTransforms`
gives way to `SelectionOutline.stickBoxes`, the twelve boxes relative to the corner (same
geometry: `gap` off the box, `thickness` across, corner to corner); the API moves under
`## Unreleased`, which already holds PF2's break.

**And the crack is one mesh a stage** (voxel_game). `FirstPersonView` builds four meshes, stage
k's holding the sticks of stages 0..k, on one node whose mesh is the current stage's: one draw
where there were up to 60. No scenario mines (the benchmark's player is creative, which breaks
at once), so the crack is checked by the profile's draws with a probe that holds a mining stage,
not A/B'd: its draws cost what the outline's do.

**Judged by** the encode p50, UI p50 and the colour pass's draws on `orbit:6 -- --aim`
(`--aim` from `d92bcc6`, the A/B's before; `aimed` 1.0 on every line), A/B in rounds A B, B A,
A B, on the phone (where the encode is the frame; the phone preset) and on the Mac. Expected:
the encode p50 back to within ~0.05 ms of the runs without the outline on the phone. Tests:
`BoxMesh`'s arrays (counts, every face's winding against `VoxelModel.arrays`', the positions
inside the boxes), `stickBoxes` (the twelve edges, `gap` off, `thickness` across, corner to
corner), the crack's stage boxes (cumulative, each on its face). A mesh cannot be built in a
`flutter test` (note 30), so the geometry's upload is seen running, not tested.

**What does not change.** The outline's look (colour, `gap`, `thickness`, `depthBias`, no
shadows), where it shows (`PlayerEntity`'s aim, a creature's drawn box), the crack's segments
and colour.

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
| — | measurement | `9c36cc2` | **The benchmark turns the view by `InputMap.turn`**, a steady rate `takeLook` integrates over its `dt` (a held stick), no longer by `look` fed from a persistent frame callback: that callback runs after paint, so each frame's turn reached the next frame and was weighed against that frame's `dt`. PF3's first probe showed it (`orbit:6` judder 0.46 with 1 still frame, the frames alternating 8.3 and 16.7 ms at ~105 fps, where `fly:6`, not turned, read 0.08). A mouse drained once a frame covers the frame's own interval, as the stick does. |
| PF3 | interpolation | `37e3190` | As §PF3, the design: `NodeBody`'s two poses (`syncNode` / `beginStep` / `drawNode`, `drawnPosition`), `VoxelGame.frame` drawing every body at the loop's `alpha` and draining the look once a frame, `drawnTime` for the bob and the pull-out, the rigs' facing on their owner's node, the creature outline per frame, rule 14's sentence on the look. One probe run each on the Mac at 120 Hz, `dpr` 2.0, against `9c36cc2`'s (above): **view judder `orbit:6` 1.03 → 0.00, `mobs:6` → 0.00, `fly:6` 1.00 → 0.05, still frames 577 → 0, 720 → 4**; `fly:6`'s four are the run's first two steps, the player held at the origin before the flight starts (√(4/1450) = 0.05), the same on both sides. The A/B follows. |
| PF3 | phone A/B | `c87a846` | **Galaxy S24, phone preset, 120 Hz** (`low_power` 0, `refreshHz` 120 and unlocked on every line), `9c36cc2` against `37e3190`, three rounds alternated (A B, B A, A B), `docs/perf/pf3_s24_phone120_ab_{9c36cc2,interp}.jsonl`, the battery 29.9–35.7 °C before and 31.1–36.4 after (a call waited for it under 36 °C: at 120 Hz it stayed over 33 for minutes). Medians of three: **view judder `orbit:6` 0.99 → 0.00, `fly:6` 1.00 → 0.05, `mobs:6` 0.79 → 0.00; still frames 687 → 0, 707 → 3, 318 → 0** (`mobs:6` read under 1 before because at ~87 fps more frames run a step; `fly:6`'s three are the flight's start, on both sides). The cost is inside the noise: UI p50 `orbit:6` 4.92 → 4.91, `fly:6` 4.71 → 4.61, `mobs:6` 6.36 → 6.05; UI p99 `orbit:6` 7.97 → 8.43 (runs 7.86–8.93 → 8.39–18.4, the high one the warmest run), `fly:6` 6.94 → 7.32 (6.82–7.21 → 7.15–7.32); step p99 `fly:6` 2.65 → 3.09 (2.45–3.18 → 2.03–3.40), `mobs:6` 8.96 → 8.44; fps and frame p99 unchanged (`orbit:6` 118, `fly:6` 119, `mobs:6` 87 → 90 within 82–93 on both). Two USB drops, no line lost; one `orbit:6` of the before side died in the Adreno driver (`KL-008`) and was rerun. |
| PF3 | Mac A/B | this commit | **Mac at 120 Hz, `dpr` 2.0, unlocked on every line**, `9c36cc2` against `37e3190` (its lines say `c87a846`, the same code plus docs), three rounds alternated (`docs/perf/pf3_mac120_ab_{9c36cc2,interp}.jsonl`; one `orbit:6` of the before side ran 52.6 s at 2 fps, its window covered for a while, and is set apart in `…_9c36cc2_occluded.jsonl`, replaced by a fourth run). Medians of three: **view judder `orbit:6` 0.95 → 0.00, `fly:6` 1.00 → 0.05, `fly:12` 0.98 → 0.05, `mobs:6` 0.95 → 0.00; still frames 578 → 0, 719 → 4, 658 → 3, 591 → 0** (`fly`'s are the flight's start). The cost is in the noise: UI p50 `orbit:6` 0.48 → 0.44, `fly:6` 0.48 → 0.48, `fly:12` 0.75 → 0.73, `mobs:6` 1.10 → 1.05; UI p99 `mobs:6` 2.24 → 2.85 (runs 2.24–3.60 → 2.28–3.11), the others lower; step p99 unchanged (`fly:12` 2.56 → 2.51); fps unchanged (109, 120.7, 114.6 → 113.0 inside `fly:12`'s 111.7–116.7, 110). **With the CPU held busy** (`yes` ×2, `mobs:6`, `docs/perf/pf3_mac120_busy_ab_{9c36cc2,interp}.jsonl`): UI p50 1.02 → 1.07 (1.02–1.08 → 1.04–1.16), UI p99 2.23 → 2.27, step p99 1.15 → 1.18: drawing 40 creatures between steps costs hundredths of a millisecond a frame. Seen running: `mobs` held still, the creatures upright and facing where they walk with their facing on the node. **PF3 is done.** |
| PF2 | design | this commit | §PF2, the design: a probe (stopwatches, not committed; Mac, `fly:12`) put the streaming at 78 ms in 12 s, in bursts: up to 15 applies in one frame (4.6 ms) and the leaving column's 25 removals in one frame, outside the budget, each apply and removal rebuilding its region at once; applying is 40% packing, 34% merging, 19% upload. The phone's `fly:6` hitches (16–18 in 12 s) match the bursts. So: the view rebuilds each dirty region once a frame, nearest the focus first, inside a 2 ms budget checked before each region by a cost predicted from its vertices, and packs a chunk inside the rebuild. |
| PF2 | budget | this commit | As §PF2, the design: `VoxelChunkView.apply` / `remove` keep or drop the chunk and mark its region; `rebuild(near, {budgetUsec})`, called by `GameWorld.update` after the streamer, builds the marked regions nearest the focus first, each once, while the next one's cost predicted from its vertices (pack and build rates in µs a vertex, running means) fits in 2 ms, the first always; packing happens in the rebuild; `GameWorld.isIdle` waits for the regions. Seen running: `fly:6` draws the whole window while it streams. **A/B on the Mac at 120 Hz**, `dpr` 2.0 and unlocked on every line, `72e53e9` against this commit (its lines say `72ce198+dirty`), three rounds alternated (`docs/perf/pf2_mac120_ab_{72e53e9,budget}.jsonl`). Medians of three: **sim max `fly:6` 3.82 → 1.74 ms** (runs 2.96–4.64 → 1.65–2.01), **`fly:12` 4.04 → 2.30** (3.72–4.53 → 2.10–2.61): a burst no longer lands in one frame; sim p99 1.18 → 1.10 and 2.05 → 1.86; UI p99 2.11 → 1.87 and **3.69 → 3.09**; step p99 1.37 → 1.19 and **2.60 → 1.96**; UI max `fly:12` 5.27 → 4.19 (5.14–5.89 → 4.08–4.34), `fly:6` 5.42 → 5.15 (one after run at 7.2); hitches 6 → 5 and 116 → 104; fill 405 → 396 ms and 1090 → 1041 (the budget does not slow the first fill); RSS unchanged. `fly:12` fps read 111.1 → 104.3 (after runs 112.5 · 103.8 · 104.3): two more rounds of `fly:12` alone (`docs/perf/pf2_mac120_fly12_extra_*.jsonl`) read the other way, 106.6 · 104.0 before against 112.8 · 112.1 after, sim max 4.1 · 4.2 → 2.2 · 2.4: at radius 12 the GPU is the wall (latency p50 29 ms on both) and its fps wanders 104–113 on either side. The phone A/B follows. |
| PF2 | phone A/B | this commit | **Galaxy S24, phone preset, 120 Hz** (`low_power` 0, `refreshHz` 120 and unlocked on every line), `72e53e9` against `a793549`, three rounds alternated, `fly:6` and `orbit:6` (`docs/perf/pf2_s24_phone120_ab_{72e53e9,budget}.jsonl`), the battery 28.4–31.6 °C before and 29.2–32.1 after, one USB drop (the driver waited), no line lost. Medians of three: **sim max `fly:6` 6.74 → 3.29 ms** (runs 6.66–6.90 → 2.41–4.02), sim p99 1.88 → 1.56, **step p99 2.38 → 1.78** (2.13–2.74 → 1.46–1.87), fill 1259 → 1206 ms. **What did not move: hitches (13 · 16 · 13 → 13 · 15 · 15), UI p99 (6.86 → 6.78) and UI max (14.4–22.6 → 15.9–17.1).** §PF2, the design, read the phone's `fly:6` hitches as the streaming's bursts; they are not: `orbit:6`, which streams nothing once filled, has as many (15–34 hitches, UI max 14–16 ms with sim max 0.2–2.4) on both sides, and after PF2 `fly:6`'s UI p99 is under `orbit:6`'s (6.78 against 8.23). So the streaming no longer shows in the phone's tail, and packing on the worker, gated on that, is not done. fps 111 on the first run after an install on both sides (fill ~1250 ms), 119–120 otherwise: the order, not the code. **PF2 is done.** The phone's ~15 ms UI frames with no simulation in them are the next lead (a trace: GC, PF9's question, or encode). |
| — | tooling | this commit | `run_benchmark.dart --android` waits for the battery under `--max-temp` (36 °C by default) before each run, so a phone A/B needs no driver script to hold the temperature; 36, not 33, is the base (§Method, Phones). |
| PF4 | design | `b7126ca` | §PF4, the design: the HUD is rebuilt and repainted every frame today (a counter bumped per tick under a `ValueListenableBuilder`, and the scene's `CustomPaint` is no repaint boundary, so the route repaints the HUD with it). So: `HudBuilder` is called when the widget builds, `DefaultHud` is a tree of `HudSelector`s each rebuilt when the value it reads from the game changes, checked on `VoxelGame.frames` once a frame, and the HUD sits behind a `RepaintBoundary`. |
| PF4 | HUD | this commit | As §PF4, the design: `VoxelGame.frames` ticks at the end of every frame; `HudSelector` rebuilds a piece when the value it selects changes; `DefaultHud` is a tree of them (the hurt flash, the mining bar, the hearts, each hotbar slot, the held item's name, "click to play", "You died"); `HudBuilder` is called when `VoxelGameWidget` builds, and the HUD sits behind a `RepaintBoundary`. Seen running: the HUD of `orbit` held still is the same as before (a pixel diff of the hotbar: 0.07% of its pixels differ by more than 8 of 255, the water moving behind it). **Galaxy S24, phone preset, 120 Hz** (`low_power` 0, `refreshHz` 120, `dpr` 2.81 and unlocked on every line), `2b7a1d6` against this commit (its lines say `b7126ca+dirty`), three rounds alternated, `docs/perf/pf4_s24_phone120_ab_{2b7a1d6,hud}.jsonl`, no line lost, the battery 28.9–32.3 °C before and 30.0–32.8 after. Medians of three: **raster p50 `orbit:6` 3.78 → 1.46 ms, `fly:6` 3.72 → 1.44, `mobs:6` 2.81 → 1.11** (runs 2.59–3.92 → 1.46–1.48, 3.62–3.77 → 1.41–1.46, 2.72–2.85 → 1.09–1.22), raster p99 5.04 → 1.99, 7.42 → 4.43, 7.70 → 4.84: the raster thread no longer composites a new HUD picture every frame; **UI p50 `fly:6` 4.72 → 4.21** (4.63–4.76 → 4.19–4.33), `orbit:6` 5.05 → 4.57 (4.49–5.14 → 4.47–4.60), `mobs:6` 6.03 → 5.89 (the ranges overlap); UI p99 `fly:6` 6.84 → 6.11 (6.71–7.00 → 5.94–6.41), `orbit:6` 8.63 → 8.11 (overlap); **RSS −30 MB** (`orbit:6` 333 → 304, `fly:6` 315 → 281, `mobs:6` 296 → 263, the last two without overlap); hitches `fly:6` 11 → 8, `orbit:6` 35 → 29; encode p50 unchanged (4.00 → 4.03, 3.63 → 3.64, 4.47 → 4.68); fps unchanged (`orbit:6` 118 → 119, `fly:6` 120, `mobs:6` 91 → 92 inside 81–95 on both). `mobs:6` step p99 read 8.91 → 9.82 with no step code changed: **with the CPU held busy** (`yes` ×4, `mobs:6`, the battery 32.7–34.0 °C on both sides, `docs/perf/pf4_s24_phone120_busy_ab_{2b7a1d6,hud}.jsonl`) step p99 is 4.30 → 4.08 (3.62–6.33 → 3.71–4.35), UI p50 3.07 → 2.89 (3.06–3.40 → 2.85–3.07), raster p50 1.51 → 0.58, 120 fps on both: the clock again, as in PF7. The Mac A/B follows. |
| PF4 | Mac A/B | this commit | **Mac at 120 Hz, `dpr` 2.0, unlocked, every run 12 s**, `2b7a1d6` against `c8c11c8` (its lines say `f40b14b`, the same code plus the runner), three rounds alternated (`docs/perf/pf4_mac120_ab_{2b7a1d6,hud}.jsonl`). Medians of three: **fps `orbit:6` 109.0 → 111.5** (108.9–109.2 → 110.8–111.6), **`mobs:6` 109.5 → 112.6** (109.3–109.7 → 112.0–112.6), `fly:6` 120.8 → 121.0; hitches up with them (148 → 177, 149 → 171: more frames shown), `fly:6` 4 → 0; **raster p99 `fly:6` 8.81 → 1.60 ms** (8.73–9.42 → 1.46–1.72), raster p50 `fly:6` 0.56 → 0.24; GPU latency p50 21 → 49 ms at `orbit:6` and 27 → 60 at `mobs:6`, the pattern §Baseline at 120 Hz saw with the HUD's blur removed (fps up, the queue fuller): the GPU-bound Mac draws the HUD's layer cheaper when it is the same one every frame. Unloaded, the UI thread read slower where it read faster on the phone: UI p50 `mobs:6` 1.03 → 2.04, `fly:6` 0.42 → 0.65 (`orbit:6` 0.42 → 0.34), encode p50 0.76 → 1.56 and 0.31 → 0.53, step p99 1.31 → 2.81 and `orbit:6` 0.04 → 0.15, with no step or encode code changed. **With the CPU held busy** (`yes` ×2, `mobs:6`, `docs/perf/pf4_mac120_busy_ab_{2b7a1d6,hud}.jsonl`) it is the other way, and no run overlaps: **UI p50 1.05 → 0.95** (1.04–1.05 → 0.94–0.96), UI p99 2.13 → 1.95, encode p50 0.77 → 0.75, step p99 1.17 → 1.13, fps 109.9 → 112.6. So the unloaded rise is the clock (PF7): with less work a frame, the CPU runs slower. **PF4 is done.** |
| PF8 | probe | this commit (numbers; the probe is not committed) | **Where the fill goes, and what the view pays when a mesh lands.** Stopwatches on `3cfa2b9` (a worktree; its diff kept outside the tree as `/tmp/voxel_pf8_probe.patch`): each job's dispatch, start and end on its worker (`Timeline.now`, one clock for every isolate), the reply's arrival, the `SendPort.send` and the materialize on the UI isolate; each frame's streaming, rebuild and whole work; the `SoundBank.init` span; `--workers=N` overrides the pool's size. Raw lines: `docs/perf/pf8_probe_{mac120,s24_phone120}_*.jsonl` (their own format, not the runner's). **Mac** (`dpr` 2.0, 120 Hz, Mac left alone), fill of `orbit:6`, medians of three, by workers: **11 (the default) 383 ms, 8 402, 6 436, 4 480, 2 700**; the workers are busy 40% of 11 × the fill. A job-by-job timeline (20 ms buckets) says why: (a) **the first ~100 ms are lost on the UI isolate**: 24 generations go out at 20 ms, then no frame and no dispatch until ~120 ms, the span `SoundBank.init` holds it (0 → 112–281 ms; `renderWav` itself 6 ms: `SoLoud.init` and the `loadMem`s), which is PF10's; (b) in the steady part **only ~7.5 jobs compute at once**, with 30–50 waiting, and that holds with the queue kept in the pool and at most two jobs a worker (a prototype, `--depth=2`), so the Mac's throughput saturates near its eight performance cores, not at 11. Two prototypes of the pipeline: dispatching a mesh when the last generation of its ring lands (`--eager`, today it waits for the next frame's `update`: ring-ready → dispatch p50 3 ms, p99 ~85 ms) takes the fill **387 → 350 ms** (`fly:12` 1000 → 925); the pool's queue adds nothing measurable; `maxInflight` 48 is worse (the queues grow). **Galaxy S24** (phone preset, 120 Hz, `low_power` 0, 29–32 °C), fill of `orbit:6` by workers: **7 (the default) 728 ms, 6 731, 5 735, 4 768, 3 838, 2 1035**, and a mesh job costs **10.6 ms with 4 workers, 15.8 with 7** (7.8 with 2): past four the extra workers only slow the others (the little cores, and the big ones shared), the same fill for 3.8 s of CPU instead of 2.4. **The ring's copy is the phone's UI cost when a mesh goes out**: `SendPort.send` of the nine volumes (288 KB) p50 40–90 µs, **p99 0.9–1.6 ms, max ~2 ms**, inside the frame (the dispatch runs in `update`); in `fly:6` the frames where meshes land read p99 7.3–8.3 ms against 5.8 for the rest (rebuild p99 ~1.1 ms of it), UI p99 6.1–6.3 overall; on the Mac the same send is p50 ~20 µs, max 0.2–0.6 ms. The phone's frames with a worker computing are not slower (p50 3.0 against 4.0 ms, the clock again), and its UI max of ~14.5 ms falls in frames with no worker job at all (PF9's lead, not the pool's). |
| PF8 | design | this commit | §PF8, the design: (1) the pool is two thirds of the cores (Mac 8, S24 5); (2) the ring sent as nine addresses of volumes the pool's `generate` allocated in native memory, found by a static `Expando`, so `ChunkJobs.mesh` keeps its type and no API breaks, the pool holding each ring until its reply or its worker's exit; (3) a mesh dispatched when its ring's last generation lands, only the meshes around that chunk. Built (1), (3), then (2) only if the phone's frames in which meshes land still read over the others; one A/B of three sides for (1) and (3) against `3cfa2b9`. |
| PF8 | size | this commit | As §PF8, the design, (1): `ChunkWorkerPool.defaultWorkers` is `workersFor(Platform.numberOfProcessors)`, two thirds of the cores, at least one (12 → 8 on the Mac, 8 → 5 on the S24). Measured in the A/B of (1) and (3) together, three sides against `3cfa2b9`. |
| PF8 | eager mesh | this commit | As §PF8, the design, (3): a generation's `then` calls `_meshAround`, which dispatches the mesh of each of the nine chunks around the one that landed when it is pending, idle and its ring complete, inside `maxInflight`; `_dispatch`'s mesh send is `_dispatchMesh`, shared. A test: after one `update` of a radius-1 window (25 generations, the cap 24) the landings send `(0, 0)`'s mesh and no generation, and the sink gets nothing until the next `update`. Measured in the three-side A/B with (1). |
| PF8 | A/B | this commit | **(1) and (3), three sides against `3cfa2b9`**: `3cfa2b9`, `8fa2a01` (1, the pool's size) and `e13e5fa` (1 + 3, the eager mesh), rounds A B C, C B A, A B C, 120 Hz, unlocked on every line. **Mac** (`dpr` 2.0, every run 12 s, `docs/perf/pf8_mac120_ab_{3cfa2b9,size,eager}.jsonl`), runs of the three sides: **fill `orbit:6` 377–401 → 381–420 → 350–352 ms, `fly:6` 390–405 → 400–424 → 348–368, `fly:12` 992–1018 → 1089–1108 → 909–923** (−10% with both, no overlap; the size alone costs the Mac 9% at radius 12, which the eager dispatch more than wins back); RSS `orbit:6` 261–278 → 249–266 → 262–267, `fly:6` 275–286 → 267–270 → 273–277; fps unchanged (GPU-bound). **With the CPU held busy** (`yes` ×2, `fly:6`, `pf8_mac120_busy_ab_*`), no overlap: fill 399–403 → 435–463 → 355–388; **UI p99 1.42–1.48 → 1.63–1.70 → 1.76–2.07 ms**, step p99 0.92–0.99 → 1.00–1.07 → 1.06–1.31: meshes landing closer together fill the rebuild's 2 ms budget more often, a cost well inside the 8.3 ms frame. **Galaxy S24, phone preset** (`dpr` 2.81, battery 28–32 °C, no line lost, `pf8_s24_phone120_ab_*`): fill unchanged (`fly:6` 715–760 → 710–748 → 713–769; `orbit:6` 931–1266 on every side, its first fill sharing the UI isolate with `SoundBank.init`); `fly:6` RSS 274–275 → 269–270 → 269–271; `fly:6` UI p99 5.71–5.97 → 5.88–6.47 → 6.00–6.21, sim max 2.78–8.61 → 2.31–3.59 → 2.74–3.25; `orbit:6` encode p50 3.90–4.11 → 4.08–4.18 → 3.96–4.14 and hitches 17–27 → 25–31 → 27–35 with no worker busy after the fill (unexplained, the clock suspected). The phone's busy-CPU series (`pf8_s24_phone120_busy_ab_*`) judges nothing: the battery reached 36–37 °C with four `yes` and two runs of the size side throttled to 75 and 86 fps (note 6). **The probe on the phone** (`fly:6`, the probe re-applied on `3cfa2b9` and ported onto `e13e5fa`, three rounds alternated, a throwaway run after each install, 31–33 °C, `docs/perf/pf8_probe_s24_phone120_ab_{3cfa2b9,eager}.jsonl`): **the workers' CPU over the fill 3.83–3.88 → 2.89–2.95 s (−24%)** for the same fill (738–757 → 737–751 ms), a mesh job p50 14.8–15.2 → 11.9–13.1 ms; the frames in which meshes land (~87 of ~1430) p99 6.6–9.7 → 9.2–10.8 ms against 5.4–5.8 → 5.7–6.2 for the others; UI p99 5.91–6.08 → 6.28–6.63. **The ring's `send` p99 1.26–2.19 → 0.30–4.59 ms, max 1.8–2.3 → 0.6–5.7**: the same 288 KB, sent now at the moment a generation lands, when the workers allocate most, takes up to 5.7 ms, where copying it is tens of µs. So the tail is a wait, the isolate group's collection most likely, not the copy. **(1) and (3) are kept**: −10% fill on the Mac, −24% of the workers' CPU on the phone, for ~0.3–0.5 ms of UI p99 inside the budget. |
| PF8 | trace | this commit (numbers; the trace build is not committed) | **Who stops the UI isolate: a Dart timeline of the phone, and (2) dropped.** The probe on `e13e5fa` in a **profile** build, with timeline spans around each job's `send` (UI isolate) and its compute (worker), an instant at each reply, and `stream`, `rebuild`, `encode` spans in the frame; `flutter run --profile --endless-trace-buffer --dart-define=BENCH="… --hold"` (the example keeps running after its line), the streams `Dart, Embedder, GC, Isolate, VM`, the timeline fetched with `vm_service`'s `getVMTimeline` before the app exits (patch and tools outside the tree, `/tmp/voxel_pf8_trace_e13e5fa.patch`, `/tmp/voxel_pf8_trace_tools/`). Galaxy S24, phone preset, 120 Hz, `low_power` 0, 27.5–31.9 °C, **4 × `fly:6`, 2 × `orbit:6`**, the 12 s after fill + 2 s. A collection runs on the thread of the isolate that triggered it (`1.ui` or a `DartWorker`; the event carries only the group's id), and its end event carries the heap before and after. **The group allocates 971–979 MB of new space in `fly:6`'s 12 s (81 MB/s), 220–221 MB in `orbit:6`'s (18.4 MB/s: the UI isolate alone, no job after the fill)**; the ring's copies are 156 meshes × 288 KB = **44 MB, 4.5% of it**, so the workers allocate ~59 MB/s, three quarters. In `fly:6`: 42–49 scavenges triggered by the workers (64–70 ms), 20–30 by the UI isolate at idle (`NotifyIdle`, between frames, 52–69 ms), 1–5 by it inside a frame or a message; 36–38 old-generation finalizations, 16–21 of them inside a UI frame (23–37 ms, max 2.7–4.6). **The frames in which meshes land read p99 4.4–6.7 ms when no collection overlaps them (24–32 frames a run) and 9.8–10.4 when one does**; the quiet frames without one 6.8–6.9. So the landed frames' tail is the group's collections, which the workers' allocations drive, and (2) would take ~4.5% of them away: **(2) is dropped**, PF9 takes the lead. The long `send`s did not come back in the profile build at 28–31 °C: 4 over 0.5 ms in 4 runs, max 0.87 ms, two of them during a collection. **The UI max PF8's probe left to PF9 (~14 ms in frames with no job) is the sun's step**: every run, `fly` and `orbit`, holds `encode` spans of 12.5–22 ms, with no collection and no job, at 1.87, 5.20, 8.53 and 11.86 s after the fill's start, every 3.33 s, the phone preset's 2° step over a 600 s day: the static shadow cache re-rendered. In `orbit:6` the old generation is finalized every ~0.5 s (20–23 in 12 s), each freeing 1–1.5 MB while a scavenge leaves 30–60 KB and the old space's external size holds at 19.5 MB: the UI isolate allocates ~2 MB/s straight into old space (objects too large for new space), 6–7 of those pauses land in frames, max 4.5–5.9 ms. |
| PF9 | mesher context | this commit | **The workers' first garbage: a context per cell.** `ChunkMesher.build` declared the ladder's, the rails' and the fence's drawing as closures inside the cell loop; they captured the loop's variables (`x`, `y`, `z`, `id`, the colour, `ox`/`oy`/`oz`), so Dart allocated their context on **every cell of the 16 × 128 × 16 loop, 32768 a mesh**, and boxed the coordinates into it, whatever the cell held. Found with the allocation tracer (`setTraceClassAllocation` + `getAllocationTraces` of `vm_service`): in a JIT harness of the example's generator and mesher (a script outside the tree) `Context` came from `ChunkMesher.build` and nowhere else; in the Mac's **profile** build (AOT, `FLUTTER_ENGINE_SWITCHES=1 FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling`, or the tracer crashes the VM on a null sample buffer; tracing `Context` itself crashes it anyway) the workers' boxed doubles came from `toDouble` in `build`, the captured `ox`/`oy`/`oz`. The three shapes are methods now (`_ladder`, `_rail`, `_fence`); the harness's contexts from `build` go to 0 and its mesh phase allocates ~1.9 MB less a mesh (JIT's accounting). A test pins the twelve sub-block meshes (faces and a weighted sum of every value) as the old code built them. Measured with the other worker cuts. |
| PF9 | mesher surfaces | this commit | **The workers' second garbage: the surfaces' arrays.** Each `build` made four `_Surface`s of five growable arrays (`Float32List` 4096 × 3, `Int32List` 6144: 216 KB a surface, 864 KB a mesh before a vertex), doubled and copied them as they filled (a solid surface of the example's ~1100 merged faces grows positions and colours once), and returned views of them, all garbage once the worker copied the result into its `TransferableTypedData`s. The mesher keeps the four now and clears them each build; `take()` returns exact-size copies (~0.25 MB for that solid surface), so a result still outlives the next build, which a new test checks (and that a reused mesher meshes as a fresh one does). Measured with the other worker cuts. |
| PF9 | mesher views | this commit | **The workers' third garbage: the result's copies.** After the surfaces were kept, `build` still copied each array to its exact size (and the two light volumes, 64 KB), which the worker then copied again into its `TransferableTypedData`s. `ChunkMesher.buildWith(cx, cz, ring, use)` meshes the same way and hands `use` a result of views of the mesher's own arrays, valid only inside it; the pool's `_run` packs its transferables there. `build` keeps its contract (copies that outlive the next build). A test: `buildWith` hands the same mesh as `build` and returns the callback's value. Measured with the other worker cuts. |
| PF9 | names | this commit (numbers; the trace build and the tracer are not committed) | **Who allocates, named.** (a) **`mobs:6` traced** like PF8's runs (Galaxy S24, phone preset, 120 Hz, 30.9–31.4 °C, 2 runs, the build of `9eedf44` + the trace patch): the UI isolate alone allocates **58.5–60 MB/s** (18.4 in `orbit:6`: the 40 creatures add ~40 MB/s), 47–48 scavenges in 12 s (26–30 inside a frame, 45–53 ms, max 2.6), 27–29 old-generation finalizations (17–18 in a frame, max 2.3–2.9 ms); but **its tail is not the collector's**: 363–402 frames over 8.3 ms overlap none, 37–42 overlap one (the step and the encode, `stepMs` p90 6.7, `encodeMs` p99 10.8). (b) **The old space** (a new reader, `tl_old.py`: its growth inside scavenges is promotion, between collections direct): in `orbit:6` 2.3–2.8 MB/s promoted and 2.4–2.5 MB/s direct, in `mobs:6` 3.1 and 5.4; what goes direct is not named yet (objects over new space's ~256 KB limit, or lists grown past it). (c) **The three worker cuts** (the rows above), traced the same way on `9eedf44` + the cuts + the patch, 3 × `fly:6` at 28.7–30.3 °C against PF8's four: **the group allocates 407–415 MB in 12 s, 34 MB/s, against 971–979 (81)**; scavenges the workers trigger **8–10 against 42–49**; frames that overlap a collection **19–22 against 46–53**; the frames in which meshes land overlap one **11 times a run against ~35**, and read p99 **6.9 / 8.3 / 10.3 ms against 9.8–10.4** (the 10.3 overlaps none). (d) **The UI isolate's garbage, by owner**: the allocation tracer on the Mac's profile build, every class traced for 0.3–1 s (one `getAllocationTraces` without a class, samples grouped by the first frame of each library on the stack; the tracer keeps ~1 allocation in 11, so the shares hold, not the rates; the timeline gives the Mac's UI 20.6 MB/s in `orbit:6`). `orbit:6`: the first library outside the SDK is **flutter_scene 50%, flutter_gpu 23%, vector_math 16%**, Flutter 5%, the kit 5%; by the kit frame nearest the allocation, **60% is inside `Scene.renderViews`** (flutter_scene's own render), **22% under `TerrainGeometry.bind`** (13% the per-draw `FrameInfo`: `ByteData.sublistView`, `TransientArena.emplace`'s record, `BufferView`, buffer and view, a new `UniformSlot` from `getUniformSlot`, the `Pointer`s of `bindUniform`; the rest the `Pointer`s of `bindGeometryBuffers`), 6% under `TerrainMaterial.bind`, and ~5% the kit's own (`eulerYXZ`, `FirstPersonView.update`, `DayNightSky`, `FrameStats.addTimings`, the HUD's `_tick`). `mobs:6`: all of it inside `renderViews`. **flutter_scene's sites, for PF16's proposal**: a closure and its context per node per frame in `Node.scenePrePass`; per recorded draw, `SceneEncoder._depthOf` → `PerspectiveCamera.forward` (a `Vector3` subtracted, cloned and normalized) and `sceneSortDepth` (`Aabb3.center`'s clone, `Matrix4.transformed3`); `_OpaqueRecord`/`_TranslucentRecord.reset` boxing doubles; a record, a `BufferView`, a `ByteBuffer` and a view per `TransientArena.emplace`; a `UniformSlot` per `Shader.getUniformSlot`; a `Pointer` per `RenderPass` bind (flutter_gpu); `EngineLightingUniforms.packInto` boxing `int.toDouble`; `GradientSkySource.bind` copying through an iterator. Reusing the terrain's `FrameInfo` across one frame's draws needs a frame boundary `TransientWriter` does not expose (a cache by value would hand a still camera the last frame's view): not cut, a PF16 item. **Tooling** (outside the tree): the tracer needs the Dart profiler on (`FLUTTER_ENGINE_SWITCHES=1 FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling` for the macOS binary, or `SampleBlockBuffer` is null and the VM segfaults); `getAllocationTraces` per class returns the whole function table each time (408 classes took over 10 minutes; one call without `classId` takes a second); a JIT harness counts boxing AOT does not do, and `getAllocationProfile`'s accumulated sizes miss inline allocations. |
| PF9 | poses | this commit | **The per-step garbage the kit owns: a creature's pose.** Every step every creature posed every part (`RigInstance.animate` → `RigPart.apply`) and was placed (`RigInstance.place`), and every frame every body between two poses was drawn (`NodeBody._write`): `eulerYXZ` built three axis vectors, three axis quaternions and two products (eight objects, each with its `Float32List`), `apply` two vectors more, and the node's `rotation` and `scale` setters each rebuilt the matrix as a new `Matrix4` (`DecomposedTransform.toMatrix4`); `_write` a closure per call. With 40 creatures of ~8 parts that is ~20 000 poses a second. `eulerYXZInto` (voxel_engine) writes the product into a given quaternion, by hand; `RigPart.apply`, `NodeBody._write` (voxel_scene) and `RigInstance.place` (voxel_game) compose their pose in a static scratch and write it with one `mutateLocalTransform` through a static tear-off. Tests: `eulerYXZInto` against the product of the three `axisAngle`s over 200 random angles, and two parts posed in turn each keep their own `Matrix4.compose` of their pose (a rig cannot be built without a GPU in a test, so `place` has none of its own). Measured with a trace of `mobs:6`. |
| PF9 | workers A/B | this commit (lines: `docs/perf/pf9_{s24_phone120,mac120}_ab_{9eedf44,workers}.jsonl`) | **The three worker cuts in release**, `9eedf44` against `8d2c60f`, rounds A B, B A, A B, `--repeat 1`. **Galaxy S24** (phone preset, 120 Hz, `low_power` 0, 29.0–33.2 °C): **`fly:6` fill 735–784 → 546–573 ms (−27%)**; fps at the display's 120 on both sides; UI p99 6.14–6.37 → 5.90–6.36 (median 6.18 → 5.91), the rest inside the spread; `orbit:6` 117–119 fps on both, UI p99 7.65–8.85 → 8.24–8.59, its fill 735–1281 → 575–1005 (each side's first run after an install reads ~1000–1300, note 21). **Mac** (`dpr` 2.0, 120 Hz, unlocked, left alone, every line 12.0 s): **fill `fly:6` 368–374 → 284–328 ms, `orbit:6` 343–374 → 286–290 (−19–20%)**; `fly:6` 120.7 fps on both, UI max 4.59–5.23 → 3.48–4.35; `orbit:6` 110.6–113.4 → 111.0–111.5 fps (GPU-bound); UI p99 bimodal on both sides (0.9 or 2.0 ms, the clock), `fly:6` UI p50 0.37–0.45 → 0.49–0.67 with its encode p50 0.33 → 0.44, which the cuts do not touch: the clock reading a cheaper frame. The fill is where the workers' garbage cost: a mesh is quicker without 32768 contexts and the collections they drove. |
| PF9 | poses A/B | this commit (lines: `docs/perf/pf9_s24_phone120_ab_poses_{workers,poses}.jsonl`) | **The poses, traced and in release.** Traced like (a) of the names row, `mobs:6` × 2 at 33.3–33.4 °C on the worker cuts + the poses: the UI isolate allocates **44.9–45.9 MB/s against 58.5–60**, **promotes 0.47–0.50 MB/s into old space against 3.1–4.2** (each pose's new matrix lived a step, long enough to be promoted), and its old-generation collections free 71–75 MB against 112–128; its direct old-space growth holds (5.0–5.2 MB/s against 5.3–5.4). **Release A/B on the Galaxy S24**, `8d2c60f` (the worker cuts) against `cd8fcd2`, `mobs:6`, rounds A B, B A, A B, both sides at 35.5–35.9 °C: **fps 81.7–90.4 → 82.8–101.8 (median 90.3 → 101.8)**, **UI p99 17.2–17.8 → 14.2–15.6 ms**, **`stepMs` p50 1.17–1.19 → 0.76–0.91, p99 9.6–10.8 → 7.4–8.7**, hitches 326–341 → 222–324, encode p50 4.6–4.8 → 2.7–4.8. The UI and step ranges do not overlap. |
| PF10 | measured, not a step | this commit (lines: `docs/perf/pf10_{s24_phone120,mac120}_probe_*.jsonl`, the probe's own format: the runner's line and a `probe` object; the probe is not committed) | **The audio does not hold the UI isolate: there is nothing to move off it.** flutter_soloud 4.1.7 already opens the device on an isolate of its own (`initEngine` through `Isolate.run`) and loads each sound on another (`loadMem` through `compute`); what `SoundBank.init` runs on the UI isolate is `renderWav`, 6–13 ms in all (PF8's probe), in ~40 pieces between `await`s. A probe on `962dea7` (the benchmark's `--sound=off`, each of the first encodes timed from `ready`, the bank's span) run with the sound on and off alternated, `orbit:6`, judged by the fill: **Galaxy S24** (phone preset, 120 Hz, 31–33 °C) **fill on 569–603 ms, off 534–618**, the bank's span 238–327 ms with its awaits resuming between frames; **Mac** (`dpr` 2.0, 120 Hz, left alone) **on 279–281, off 280–286**; the first encode ~28 ms on the phone and ~15 on the Mac on both sides, none after it over 19 ms. **What PF8 read as the bank is a cold pipeline cache.** The first run after an install (the phone reinstalled before each run, two runs a side) or after a build (the Mac) encodes its first frame for **340–361 ms and a later one for 269–291** on the phone (513 and 257 on the Mac), with the sound on or off, and fills in **1080–1169 ms** (983 on the Mac) against ~560 (~280) warm: Impeller compiles each pipeline on its first use and keeps it after. The bank's span held those encodes because its awaits could not resume during them. Every traced phone run (`flutter run --profile` installs each time) is such a first run: both encodes are in all 13 traces of PF8 and PF9, in their first ~0.6 s. **PF10 is dropped.** A player pays that compile once per install; only a warm-up of every pipeline before the game shows would move it, which is flutter_scene's (lead (3) below). |
| PF11 | design | `d77fe41` (the probe is not committed) | §PF11, the design: a probe (a standalone AOT program, the host on one isolate, N peers draining loopback sockets on another, the messages of `sessions.dart`) confirmed the premise before the design (note 32): on the Mac a `state` of 40 creatures costs the host **369 µs with 4 peers and 797 with 8**, encoded once per peer, against 106 and 122 encoded once into one buffer; **113 edits in one step cost 1.7 ms with 4 peers (p99 3.0) and 3.3 with 8 (p99 5.9)**, a `set` message and a write each per peer, against 37 and 50 µs as one message. So (1) a broadcast is encoded once (`EncodedMessage`, `NetConnection.sendEncoded`, voxel_engine), (2) the edits leave once a step as one `edits` message, the session ticked last in the step (voxel_game), and the benchmark gets `--peers=N` (scripted peers on an isolate) and `--edits=N` (a burst a second), the A/B's before. |
| — | measurement | `fe5bf26` | `benchmark.dart --peers=N --edits=N` (§Method, a host with peers). One smoke run each on the Mac, before PF11's cuts: `orbit:6 -- --peers=4 --edits=125` step p50 0.08 ms, **p99 2.58, max 5.67** (12 bursts), fps 113; `mobs:6` with the same flags step p99 3.82, max 6.49. |
| PF11 | encode once | `85f760a` | As §PF11, the design, (1): `EncodedMessage` (the message's JSON line in UTF-8, made once) and `NetConnection.sendEncoded` (one write); `NetHost.broadcast` encodes once for every peer, and `send` is one write too. A test: one broadcast of 20000 numbers reaches two peers whole, `except` skips one, and one encoding sent to both arrives at both. Measured in the A/B with (2). |
| PF11 | edits per step | `799192a` | As §PF11, the design, (2): `HostSession` and `ClientSession` queue the step's edits (x, y, z, id) and send them as one `edits` message when they tick, which is now the last thing `VoxelGame.step` does (after the systems and `onTick`), every step with an edit; the receiver stores them in order; `set` is gone from the wire. A test: 50 cells and one of them again, edited between two steps, reach a raw peer as one message of 51 edits ending with the second edit, and a client ends with every cell, the twice-edited one as the last edit said. Measured in the A/B with (1). |
| — | fix | `6065a07` | **An Android release could neither host nor join**: Flutter's template grants `INTERNET` to the debug and profile manifests only, so the phone's first `--peers` run failed at `ServerSocket.bind`. The example's main manifest declares it, and voxel_game's README tells a game to. The A/B's three worktrees carry the same line uncommitted (their lines say `+dirty`). |
| PF11 | phone A/B | `5f98c1c` (lines: `docs/perf/pf11_s24_phone120_ab_{fe5bf26,encode,batch}.jsonl`) | **Galaxy S24, phone preset, 120 Hz** (`low_power` 0, `refreshHz` 120 and unlocked on every line, 30.7–35.9 °C), three sides in rounds A B C, C B A, A B C: `fe5bf26` (the measurement), `85f760a` ((1), encode once) and `799192a` ((1) + (2), edits per step), every scenario with `-- --peers=4 --edits=125`, a discarded 3-s warm-up run after each install (note 21), no run lost. Runs of each side: **`orbit:6` step p99 21.2–22.3 → 16.3–19.6 → 1.38–1.46 ms, max 26.9–30.2 → 25.5–28.7 → 1.66–1.71**: the burst's step held the phone's UI thread for ~20 ms, three frames at 120 Hz, far past the Mac probe's 1.7 ms × ~2.4 (a socket write costs the phone much more), and now costs what a quiet step does; **frame p99 16.6 → 16.6 → 8.4 ms** (two of three runs), UI p99 8.5–12.9 → 10.0–13.6 → 6.6–8.5, fps 109–117 → 109–118 → 118–120. **`mobs:6` step p50 1.88–1.95 → 1.33–1.34 → 1.27–1.34 ms**: the 5.8 KB `state` encoded four times cost ~0.6 ms of every step's median (it goes out every third step), which (1) takes; **step p99 19.0–20.7 → 13.8–18.6 → 8.0–8.5**, UI p99 18.4–21.2 → 16.5–20.1 → 14.9–15.3, frame p99 25.0 → 25.0 → 16.7 (two of three), fps 85–92 → 92–94 → 93–96. Encode, fill and RSS unchanged. |
| PF11 | Mac A/B | `73652c3` (lines: `docs/perf/pf11_mac120_ab_{fe5bf26,encode,batch}.jsonl`) | **Mac at 120 Hz, `dpr` 2.0, unlocked, left alone, every run 12 s**, the same three sides and rounds, each build warmed by one discarded run (note 31). Runs of each side: **`orbit:6` step p99 2.49–2.53 → 1.96–2.02 → 0.16–0.56 ms, max 3.0–5.0 → 2.3–4.4 → 0.40–0.98**; **`mobs:6` step p50 0.64–0.68 → 0.59–0.60 → 0.56–0.62, p99 3.4–4.8 → 2.8–3.3 → 2.5–2.7, max 6.0–8.0 → 4.8–6.7 → 2.8–3.6**; UI p99 `mobs` 5.4–5.9 → 4.8–5.3 → 4.9–5.2; fps 110–113 on every side, encode and frame p99 unchanged (the Mac is GPU-bound). **PF11 is done**: with 4 peers a burst of 125 edits costs the host's step what a quiet step does, on both machines, and the `state` goes out encoded once. |
| — | measurement | `d92bcc6` | `benchmark.dart --aim` (§Method, the selection outline): the player's reach 160 m, the line's `aimed`. One smoke run each on the Mac: at a 64 m reach `orbit:6` aimed 0.67 of its steps (the look passes over a valley for a third of the turn) and `mobs:6` 0.89; at 160 m `orbit:6` aims the whole turn (1.0). |
| PF12 | design | `a6b2c60` (the probe is not committed) | §PF12, the design: flutter_scene's profile on `d92bcc6`, `orbit:6` with and without `--aim`, confirmed the premise before the design (note 32): the outline's twelve sticks, a geometry each, are **12 more colour draws on ~39 (+30%)**, ~35 µs of colour encode and ~10 of cull on the Mac, **~0.3 ms and ~55 µs on the phone, encode p50 3.9–4.1 → 4.3–4.4 ms, fps 119 → 117–118**. A shared unit cube batches them into one instanced draw but leaves the cull and the packing, about half (a Mac probe). So the outline becomes one mesh a box span (`BoxMesh`, voxel_scene, one node, one draw) and the crack one mesh a stage (voxel_game, up to 60 draws to one). |
| PF12 | outline one mesh | `143a713` | As §PF12, the design: `BoxMesh` (new, voxel_scene: boxes as arrays or one geometry, wound as the chunk mesher winds) and `SelectionOutline` on one node whose mesh is the twelve sticks of the shown box's size, kept by size (`stickBoxes` replaces `stickTransforms`). flutter_scene's profile on the Mac (a probe build of this commit, `orbit:6 --aim`, as the design's; two of three runs, the third slower in every pass, the shadow's too), against the design's probe: **colour draws 50.5 → 39.5, colour encode 190–192 → 162–163 µs** (157–161 with no outline), **cull 34–36 → 26** (25), **scene pass 258–263 → 222–224** (213–219): the shared cube had left 173–176, 34–36 and 244. Tests: the arrays' counts, faces on their boxes, every triangle wound as `VoxelModel.arrays`' are; the sticks' boxes. Seen running: the edges drawn around an aimed block (`mobs:6 --aim`, held still). Measured in the A/B. |
| PF12 | crack one mesh | `a191d21` | As §PF12, the design: `FirstPersonView` builds four `BoxMesh`es, stage k's holding the sticks of stages 0..k (`crackBoxes`), on one node whose mesh changes with the stage. A probe build holding the mining at 0.9 (the last stage; `--dart-define=CRACK=true`, not committed) with the outline shown: **the colour pass draws 40.5 on the Mac, the terrain's ~38.5 plus one for the outline and one for the crack's 60 sticks**, which were 72 draws. Seen running: the crack on the aimed block's faces, inside the outline. A test: the stages hold 12, 24, 42 and 60 sticks, each stage the one before it and more, every stick thin across its face, just off the cell. Not A/B'd (no scenario mines): its draws cost what the outline's do. |
| PF12 | phone A/B | this commit (lines: `docs/perf/pf12_s24_phone120_ab_{d92bcc6,outline}.jsonl`) | **Galaxy S24, phone preset, 120 Hz** (`low_power` 0, `refreshHz` 120 and unlocked on every line, 31.6–34.4 °C), two sides in rounds A B, B A, A B: `d92bcc6` (the measurement) and `143a713` (the outline as one mesh), `orbit:6 -- --aim` (`aimed` 1.0 on every line), a discarded 3-s warm-up run after each install (note 21), no run lost. Runs of each side: **encode p50 4.19–4.28 → 3.97–4.03 ms, UI p50 4.73–4.84 → 4.53–4.57**, fps 118.3–118.9 → 118.7–119.4, UI p99 8.0–8.5 → 7.8–8.7; the design's probe read the encode p50 at 3.9–4.1 with no outline (a profile build): the outline now costs the phone about nothing. |
| PF12 | Mac A/B | this commit (lines: `docs/perf/pf12_mac120_ab_{d92bcc6,outline}.jsonl`) | **Mac at 120 Hz, `dpr` 2.0, unlocked, left alone, every run 12 s**, the same sides and rounds, each build warmed by one discarded run (note 31). Runs of each side: **encode p50 0.35–0.36 → 0.30 ms** (0.30 with no outline, the design's probe), **UI p50 0.39–0.40 → 0.33–0.34**, fps 110.8–111.5 on both sides (the Mac is GPU-bound). **PF12 is done**: the outline is one draw and the crack one more, where they were up to 72. |
| PF16 | sent | `8c2f7fe` (the draft) · this commit (sent) | **Sent as one issue with the owner's ok on the text, unchanged: <https://github.com/bdero/flutter_scene/issues/435> (2026-09-29, `docs/FLUTTER_SCENE_PROPOSAL_2026-09-29.md`).** What comes back from upstream is followed there; nothing in the kit waits for it. flutter_scene 0.23.0's render path read (line numbers in the draft), and the step's two premises corrected. (a) **The shadow cache**: any change of the light direction over `1e-10` (squared) clears every entry (`render/shadow_cache.dart:101-116`), so each sun step re-culls the static world and re-renders every cascade in one frame, unamortized (`:132-135`), each into a new texture (`render/shadow_pass.dart:246`); `maxAmortizedRefreshes` and the slack are `static const`; the ask: mark the tiles stale on a direction change so the amortized path refreshes one a frame, keep the textures. (b) **The per-draw encode**: the sites of PF9's names row confirmed at 0.23.0 (`scenePrePass`'s two closures a node, five `Vector3`s a record in `_depthOf`, `emplace`'s buffers and views, a `UniformSlot` a `getUniformSlot`, a record key a `resolvePipeline`); and **the encoder memoizes `FrameInfo` only for `UnskinnedGeometry`** (`scene_encoder.dart:789-804`): `TerrainGeometry`, a custom `Geometry`, emplaces it every draw, the 13% of PF9's trace, and cannot cache it itself (arena blocks recycle mid-frame). (c) **"Skip absent vertex streams"** holds for `MeshGeometry` (six streams, 72 B, whatever was given: `geometry/geometry.dart:1059-1081`); PF13 already left it for the terrain, so the ask is a public custom-`Geometry` contract (the kit imports `src/` and pins 0.23.0 exactly). (d) **"Sort opaque draws front to back" is not what the step said**: the comparator keys pipeline, material, geometry (`identityHashCode`), lights, fade and only then depth (`scene_encoder.dart:1058-1080`), so regions draw in hash order although the class doc says front to back; not measured, and little expected on Apple's HSR and Adreno's LRZ: written as a question. (e) **The pipeline warm-up exists**: `Scene.warmUp(views, includeOffscreen: true)` (`scene.dart:1397`; `SceneView(warmUp: true)`), which the kit does not call (`voxel_game_widget.dart:270`): lead (3) is the kit's, not upstream's. |
| PF17 | done | this commit (lines: `docs/perf/pf17_{mac120_ab,mac120_trace,s24_phone120_ab}_*.jsonl`) | §The final measurement (PF17), one sitting, no run lost. **Mac, release**, `67da3ac` against `b49ec54`: `orbit:6` 100.4 → 111.3 fps, `orbit:12` 77.2 → 96.6, `fly:6` 118.8 → 120.7 (the display), `fly:12` 97.8 → 118.1, **`mobs:6` 46.8 → 112.8**; UI p50 −54 to −87% but flying, RSS −14 to −30%. **Mac, GPU a frame** (`--trace`): `orbit:6` 10.1 → 8.8 ms, `orbit:12` 13.5 → 10.7, `fly:6` 8.3 → 7.6. **Galaxy S24, 120 Hz**, `797de1d` desktop look → PF1 alone → the tip: `orbit:6` 36 → 69 → **118**, `orbit:12` 21 → 60 → **80**, `fly:6` 37 → 109 → **120**, `mobs:6` 19 → 26 → **94**; RSS −28 to −44%. The ceilings: on the Mac the GPU paying for pixels at `dpr` 2.0 (8.8 ms at `orbit:6` against 8.3), on the phone flutter_scene's encode on the UI thread (7.0 of 7.5 ms at `orbit:12`), both past what the kit owns. |

**Where the work stopped (2026-09-29, PF17 done: the plan is complete).** Last commit: this one (`docs:`, PF17, §The final measurement, its row, its lines and this paragraph), over `b49ec54` (`docs:`, PF16 sent), `8c2f7fe` (`docs:`, PF16's draft), `60b9a9a` (`docs:`, PF12's phone and Mac A/B), `a191d21` (`voxel_game:`, the crack one mesh a stage), `143a713` (`voxel_scene:`, the outline one mesh, `BoxMesh`), `a6b2c60` (`docs:`, PF12's design), `d92bcc6` (the benchmark's `--aim`), and PF11's `73652c3`, `5f98c1c`, `6065a07`, `799192a`, `85f760a`, `fe5bf26`, `d77fe41`; before them `7e7e33a` (`docs:`, PF10 measured and dropped), `962dea7`, `cfb81d8`, `cd8fcd2`, `b54edea`, `8d2c60f`, `70bc9e4` and `4770017` (PF9). Every code commit has its CHANGELOG line under `## Unreleased` (voxel_engine has no API break: `ChunkMesher.buildWith`, `eulerYXZInto`, `EncodedMessage` and `NetConnection.sendEncoded` are new; voxel_scene holds PF2's break and PF12's, `SelectionOutline.stickBoxes` for `stickTransforms`, with `BoxMesh` new; voxel_game holds PF4's break, PF11's wire change, `set` replaced by `edits`, and PF12's crack, `FirstPersonView.crackBoxes` new); 0.2.0-dev is on pub.dev, the next release is 0.3.0-dev. **PF12 in one line**: flutter_scene draws a geometry a draw, so the outline's twelve sticks were 12 of the colour pass's ~51 draws (~0.3 ms of the phone's colour pass, the encode p50 +0.25–0.35 ms) and the crack up to 60 more; each is now one `BoxMesh`, and a shared cube (flutter_scene's batching) would have left half of it in the cull and the packing. **PF9 is done where the kit owns the garbage**: what is left is inside flutter_scene's render (**PF16's proposal**, written with the owner's go-ahead only); reusing the terrain's `FrameInfo` across a frame's draws needs a frame boundary flutter_scene does not expose. **Three leads stay open**: (1) the UI isolate still grows its old space **directly** at ~2.4 MB/s in `orbit:6` and ~5 in `mobs:6` (not promotion: `tl_old.py`), which the allocation tracer cannot size (a sample has a class and a stack, no size); a heap-snapshot diff or a trace of the large classes only may name it; (2) the phone's slowest frames without a collection are still the sun's step re-rendering the static shadow cache (12.5–22 ms every 3.33 s with the phone preset), flutter_scene's (PF16) or a `ShadowSpec` choice; (3) the **cold pipeline cache**: the first run after an install or a build stops the UI thread for ~0.6 s (phone) to ~0.8 s (Mac) in two encodes, Impeller compiling pipelines on first use (PF10's row); flutter_scene already has the warm-up, `Scene.warmUp(views, includeOffscreen: true)` (PF16's row), so it is the kit's: call it behind a loading screen once the window has filled; it only moves the first launch, which every A/B discards, so it is a kit step, not a PF17 blocker. `KL-007` (drops and projectiles mesh a geometry each, `projectile.dart:98` a `CuboidGeometry` a projectile) now has `BoxMesh` at hand. **PF16 is sent**: <https://github.com/bdero/flutter_scene/issues/435>, one issue of four sections (the shadow cache on a stepped sun, the per-draw encode cost, a public custom-`Geometry` contract, the opaque order as a question), the text of `docs/FLUTTER_SCENE_PROPOSAL_2026-09-29.md`; a reply there is read at the start of a session, and any code it asks for is a new step. **PF17 is done and no PF step is left.** Its tools (outside the tree, in the session's scratchpad, not kept): `mac_ab.py NAME RUNS [trace]` and `phone_ab.py NAME` drivers, the worktrees `pf17_67da3ac`, `pf17_797de1d`, `pf17_tip` with the tip's runner copied in and its two edits (a line without `mode` accepted, `gpuMs` written as `gpuLatencyMs`); a later A/B against the harness redoes them from §The final measurement. **Next, outside this plan**: lead (3), `Scene.warmUp` behind a loading screen once the window fills, is a kit step (`opus 5.5:high`: it touches the loop's start and the HUD across voxel_game); a reply on bdero/flutter_scene#435 comes first if one arrived; lead (1) is a perf investigation (`opus 5.5:xhigh`); the 0.3.0-dev release by `PUBLISHING.md` is a checklist (`opus 5.5:low`). PF12's tools (outside the tree): `/tmp/voxel_pf12_tools/` (`profile_main.py`, which wraps `benchmark.dart`'s `main` in a zone printing to `stdout` on the Mac for a `FLUTTER_SCENE_PROFILE` build; `crack_probe.py`, the `--dart-define=CRACK=true` probe holding the mining at 0.9; `prof_sum.py`, the medians of the last ten profile samples and the line's encode and UI p50; `phone_prof.py`, the premise probe on the phone; `phone_ab2.py` and `mac_ab2.py`, two-side drivers). PF11's tools (outside the tree): `/tmp/voxel_pf11_tools/` (`netprobe/`, the standalone AOT probe of the design, `dart compile exe bin/netprobe.dart` and `./netprobe <peers>`; `phone_ab3.py` and `mac_ab3.py`, three-side drivers that warm each install or build with a discarded run; `internet.patch`, the manifest line for a worktree older than `6065a07`). PF10's probe (outside the tree): `/tmp/voxel_pf10_probe_962dea7.patch` (`--sound=off`, the first encodes, the bank's span) and `/tmp/voxel_pf10_tools/` (`probe.py mac|android OUT SCENARIO:RADIUS N`, sound on and off alternated; `fresh.py`, the phone reinstalled before each run). The PF9 tools (outside the tree, `/tmp` does not survive a reboot): the trace patch for `cd8fcd2` or later, `/tmp/voxel_pf9_trace_cd8fcd2.patch` (PF8's probe, the timeline spans, `--hold`), applied with `git apply` in a worktree; `/tmp/voxel_pf8_trace_tools/` (`trace_driver.py`, `tl_alloc.py`, `tl_cross.py`, `tl_frame.py`, and new: `tl_old.py`, old-space growth by promotion or direct, `tl_rate.py`, new-space MB by triggering thread); `/tmp/voxel_pf9_tools/` (`phone_ab.py`/`mac_ab.py` two-side drivers, `app_trace` and its source in `alloc_client/`, which attaches to a profile build and traces allocations, `owners.py`, which attributes its `DUMP` to libraries and kit frames, `alloc_harness.dart`, the JIT harness of the example's generator and mesher); the traces in `/tmp/voxel_pf9_traces/`. After PF13 the Mac runs `orbit:6` at ~109 fps (the GPU 8.9 ms a frame at `dpr` 2.0, 96% busy: pixels, not vertices), `orbit:12` at ~94, `fly:12` at 104–113 (GPU-bound, it wanders); the phone `orbit:6` and `fly:6` at the display's 119, `mobs:6` at 85–94: on the phone the frame is the UI thread's and the encode is draws × passes (PF12's outline, `KL-007`'s drops), not vertices. `KL-008` (the driver crash in the first two
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
only within one A/B. (17) macOS stops sending vsync to a benchmark window that is fully covered
(another app in front): the run stalls at 0% CPU, its line reads far more `seconds` than
asked and a few fps, or the runner times out after 3 minutes; the Mac must be left alone
with the window in front, not only unlocked, and a line with `seconds` over 12 is set apart.
(18) a persistent frame callback runs after paint: anything fed from it reaches the next
frame, so a scripted turn goes through `InputMap.turn`, a rate `takeLook` integrates. (19)
at 120 Hz the phone stays over 33 °C for minutes between calls; PF3's driver waited for
36 °C, both sides within 30–36. (20) the phone was found in power-saving mode again
(`low_power` 1) at the start of PF2's A/B: check it every session (it was 0 for PF4). (21) on the phone the first run after
an install reads ~111 fps and a ~1250 ms fill on either build: compare sides with the same number of
first-after-install runs, or read fps from the others. (22) **36 °C is the phone's base**, never 33: the
runner waits for it itself (`--max-temp`), so a driver script only alternates the sides and
relaunches what a failed call left; with four `yes` the battery climbs ~1 °C a run and the
first busy series of PF4 read `mobs:6` at 112 → 90 → 76 fps as it went 32.8 → 35 °C (those
lines were dropped): a busy-CPU driver waits for 36 before starting the loops and passes
`--max-temp 99`, one scenario, one run a call. (23) a Mac window opened while the user works in
another app stays behind it (`open -n` does not always bring it to the front): the pixel
diff's first after shot caught VS Code; take the shots with the Mac left alone too. (24) the probe of PF8 lives outside the tree: `/tmp/voxel_pf8_probe.patch` (apply on `3cfa2b9` in a worktree: `git apply`), its driver and summaries in `/tmp/voxel_pf8_probe_tools/` (`probe_driver.py mac|android OUT RUN...`, RUN = `scenario:radius:seconds:workers:repeat[:--flag+--flag]`; the Mac binary is run directly, the phone through `am start` and logcat); `/tmp` does not survive a reboot. The benchmark's own flags `--workers=N`, `--depth=N`, `--eager`, `--inflight=N` exist only in that probe. (25) logcat cuts a line near 1000 characters: a long probe line is printed in pieces (`[probe-fill#0] …`) and joined by the reader. (26) during the fill the Mac presents a frame every ~20 ms, not 8.3: a per-frame dispatch waits that long. (27) the allocation tracer (`vm_service`'s `setTraceClassAllocation` + `getAllocationTraces`) works on a **profile** build only with the Dart profiler on: the macOS binary takes `FLUTTER_ENGINE_SWITCHES=1 FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling`, or the VM segfaults in `SampleBlockBuffer::ReserveSampleImpl` at the first traced allocation; one `getAllocationTraces` without `classId` returns every traced class in a second (per class, each call returns the whole function table: 408 classes took over 10 minutes); the buffer keeps the **last** ~1 in 11 allocations, a contiguous slice of a few tens of ms, so a share read from it is of that slice (a `mobs:6` slice fell inside one render); tracing 3127 classes at once is fine. (28) A JIT harness (`dart run --observe`) names sites but boxes doubles at calls AOT does not, and `getAllocationProfile`'s accumulated sizes miss inline allocations: size a cut on the phone's trace. (29) A Dart closure declared in a loop body that captures the loop's variables costs a context per iteration even when the closure is never made: keep closures out of hot loops. (30) A rig cannot be built in a `flutter test` (its `MeshGeometry` needs Flutter GPU): test the pose's matrix through `RigPart`. (31) The first run of a fresh Mac build is cold too (fill ~3.5×, PF10's row), as the phone's first after an install (note 21): a Mac side built for an A/B starts with a run whose fill is not comparable. (32) A span that `await`s is not time a thread was held: before blaming what runs inside it, check that the frames stopped with it gone (PF10's `--sound=off`). (33) An Android **release** build has no `INTERNET` permission unless the app's main manifest declares it (Flutter's template puts it in debug and profile only): a socket fails there and nowhere else; an A/B side older than `6065a07` needs `/tmp/voxel_pf11_tools/internet.patch`. (34) The phone pays a socket write far more than the Mac: PF11's burst cost ~1.7 ms on the Mac and ~20 on the S24 (12×, against ~2.4× for Dart code), so a Mac probe of anything that does I/O underestimates the phone. (35) flutter_scene batches opaque draws only when they share the **same** pipeline, geometry and material objects (`opaqueBatchEnd`); a geometry per node is a draw per node, and the cull still visits every node of a batch, ~0.4 µs a node on the Mac and ~2 on the phone: a fixed group of boxes is cheapest as one `BoxMesh`. (36) The quickest check of a draw cut is a `FLUTTER_SCENE_PROFILE` build's `draws_mean` (with `/tmp/voxel_pf12_tools/profile_main.py` on the Mac; on the phone the lines reach logcat as they are); its per-pass times are comparable only between warm runs of builds of the same defines. (37) A probe that changes the game's state is simplest as a `--dart-define` read with `bool.fromEnvironment` in the benchmark (PF12's `CRACK`): the runner's flags stay untouched.

**After the plan (2026-09-29): lead (3) done, a kit step.** Last commit: this one
(`voxel_game:`, the loading screen and the warm-up). No reply on bdero/flutter_scene#435 at
the session's start. `VoxelGameWidget` now runs the game undrawn behind a loading screen
(`LoadingStage` starting → filling → warming → playing, the default `LoadingScreen` or a
game's `LoadingBuilder`), its own ticker calling `VoxelGame.frame` with the controls off
until `VoxelGame.filled` (the player placed and `GameWorld.isIdle`), then calls
`Scene.warmUp([RenderView(camera: game.camera())], includeOffscreen: true)` and only then
mounts the `SceneView` and the HUD. The `SceneView`'s own `loading`/`warmUp` gate could not
be used: it does not call `onTick` while gated, and `onTick` is what streams the window in.
**Mac, release, `orbit:6`, the app's Metal cache (`$(getconf
DARWIN_USER_CACHE_DIR)/com.remottely.voxelGameExample/…/com.apple.metal{,fe}`) cleared
before each cold run**, a probe printing every encode over 20 ms (not committed), two runs
a side: before, cold, the first frames shown encode in 641 + 324 + 575 and 654 + 319 + 568
ms, fill 1724–1727 ms; after, cold, one warm-up encode of 1062–1064 ms behind the screen,
the first frame shown 1.3 ms and none over 20 ms after it, fill 1306–1339 ms (the
benchmark's fill check lands a frame after the kit's, so it holds the warm-up). Warm, the
warm-up costs 4 ms and the fill is unchanged (231–281 against 279–302 ms). The Mac's cache
is the bundle id's, shared by every build of the example: a cold A/B clears it before each
cold run, or the first side warms the second. Not measured on the phone. Warmed is what the
filled window holds: a pipeline first used later (a creature's rig, a drop, water not in
the window, where its pipeline differs) still compiles in the frame that first draws it. **Next**: lead (1) is a perf
investigation (`opus 5.5:xhigh`); the 0.3.0-dev release by `PUBLISHING.md` is a checklist
(`opus 5.5:low`: the versions moved in `34d7a6e`, pub.dev still has 0.2.0-dev, and this
step's CHANGELOG line is under `## 0.3.0-dev`); a phone check of the cold start (a fresh install, `am start`, the same
probe) would confirm the phone's ~0.6 s moved too (`opus 5.5:medium`).
