# Performance: Flutter POC vs Godot POC (2026-09-11)

**Question.** The Flutter POC is a file-by-file port of the Godot POC. Same world, same
seed, same probe. How do the two compare at runtime, and where does the difference live?

**Answer.** Terrain generation and meshing cost the same or less in Dart than in C#; the
measured gap comes from the isolate pool size, not the language. Rendering is where Godot
wins: it holds the 120 Hz vsync cap at 2.3 M faces, while `flutter_scene` drops to 70 fps
at 2.2 M. At the default render distance (radius 8) both are playable.

## Setup

| | Godot POC | Flutter POC |
|:---|:---|:---|
| Commit | `82ff6b52e` (branch `poc_cubeworld`, `tessera_project`) | `a410edfc` (branch `poc_cubeworld`, this repo) |
| Roadmap | 35 of 35 stages | 23 of 35 stages |
| Runtime | Godot 4.7.1 mono, editor run, C# Debug assembly | Flutter macOS **release** build (debug numbers listed apart) |
| Worker model | C# on `WorkerThreadPool` (all cores) | pure Dart on `ChunkWorkerPool`, **3 isolates** by default |

Common to both: Apple M2 Pro, 16 GB, macOS; 1600x900 window; vsync on (display cap
120 Hz); `--new --seed=42`; load radius 8 unless the table says otherwise.

**Scope caveat.** The Flutter port is 12 stages behind, so Godot simulates more per frame
(redstone, rails, the underworld) and emits about 7% more faces for the same window. The
render and mesher comparison is fair because the face load is close; a whole-game
comparison would be premature.

## Results

### Window fill time (generation + meshing), ms

The `[probe] window filled` line both POCs print: from the first probe frame until the
world reports idle.

| Radius (chunks) | Godot C# | Flutter, 3 isolates | Flutter, 10 isolates | Flutter debug (JIT), 3 isolates |
|:--|--:|--:|--:|--:|
| 8 (361) | 766 | 903 | 583 | 1242 |
| 12 (729) | 1478 | 1815 | 1135 | 2183 |
| 16 (1225) | 2274 | 2981 | 1956 | 3383 |

Godot varied about ±5% between runs (781 / 1364 / 2206 on a second pass).

The 10-isolate column is an experiment: `ChunkWorkerPool(..., {this.workers = 10})`,
rebuilt in release, measured, then reverted. It is not the committed default.

### Sustained FPS after 900 settle frames

Godot: `--print-fps` (every line of the run sat at 119-121). Flutter: the probe's
`[probe] fps` line, a 0.5 s average taken right before the capture.

| Radius | Godot | Flutter release, 3 isolates | Flutter release, 10 isolates |
|:--|--:|--:|--:|
| 8 | 120 (vsync cap) | 112 | 120 |
| 12 | 120 (vsync cap) | 90 | 88 |
| 16 | 120 (vsync cap) | 70 | 78 |

Godot never left the cap, so its real headroom is unmeasured.

### Peak resident memory, MB

`/usr/bin/time -l`, maximum resident set size of the whole process.

| Radius | Godot | Flutter release | Flutter debug |
|:--|--:|--:|--:|
| 8 | 525 | 406 | 725 |
| 12 | 578 | 638 | 891 |
| 16 | 663 | 810 | 1192 |

### Render load (faces emitted)

| Radius | Godot | Flutter |
|:--|--:|--:|
| 8 | 649,942 | 608,562 |
| 12 | 1,415,049 | 1,296,129 |
| 16 | 2,341,591 | 2,165,569 |

### Build

| | Godot | Flutter |
|:---|--:|--:|
| Incremental build | 2.1 s (`dotnet build`) | 22 s debug · 37 s release |
| App bundle | not exported | 59 MB release `.app` |

## What it means

- **The mesher is not the bottleneck to port.** Dart on isolates matches C# once the pool
  uses the cores: 10 isolates beat `WorkerThreadPool` at every radius. The 3-isolate
  default leaves most of an M2 Pro idle. A port should size the pool from
  `Platform.numberOfProcessors`, not a constant.
- **Rendering is the gap.** Frame rate falls with face count on `flutter_scene` and stays
  flat on Godot's Forward+ renderer. More isolates do not move it (88 vs 90 at radius 12),
  which places the cost on the raster side. The next measurement worth taking is a frame
  timeline (`flutter run --profile` + DevTools) at radius 16, split into UI vs raster.
- **Memory grows faster in Flutter.** Lower at radius 8, 22% higher at radius 16. The
  per-chunk mesh arrays held on the Dart heap alongside the GPU buffers are the first
  suspect; not verified.
- **Never measure the debug build.** JIT adds 13-37% to fill time and 23-72% to peak memory
  (against release runs of the same length). Every number that informs a decision comes from release or profile.

## Reproduce

```bash
# Godot POC (from its poc_cubeworld/)
dotnet build
for R in 8 12 16; do
  /usr/bin/time -l /Applications/Godot_mono.app/Contents/MacOS/Godot --print-fps --path . \
    ++ --new --seed=42 --slot=perf$R --radius=$R --frames=3000 --settle=900 \
    --screenshot=/tmp/g_r$R.png 2>&1 | grep -E "window filled|Project FPS|maximum resident"
done

# Flutter POC (from this poc_cubeworld/)
flutter build macos --release
for R in 8 12 16; do
  /usr/bin/time -l build/macos/Build/Products/Release/voxel_game_minecraft.app/Contents/MacOS/voxel_game_minecraft \
    --new --seed=42 --radius=$R --frames=3000 --settle=900 \
    --screenshot=/tmp/f_r$R.png 2>&1 | grep -E "window filled|probe\] fps|maximum resident"
done
```
