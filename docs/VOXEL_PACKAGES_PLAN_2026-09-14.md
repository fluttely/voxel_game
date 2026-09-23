# Voxel Packages Plan — `voxel_core` + `voxel_scene`

> **The executable plan for growing two packages out of this POC.** Written 2026-09-14.
> Stable IDs (`VP<phase>.<step>`) — reference them in commits.
>
> **Where this lives, and why it never leaves.** Everything here stays on branch
> `poc_cubeworld`. It is never merged into `dev` or `main`, and `dev` carries no reference to
> it. The POC's history is ours to rewrite. When the API is stable, the two packages are copied
> into a **brand-new git repository as one commit, version `0.0.1`, with one initial
> `CHANGELOG.md`** — no history travels. Until then there is no per-package changelog and no
> version beyond `0.0.0`.
>
> **The rule of every step: the POC keeps working.** A file moves into a package, and the POC
> imports it from there in the same commit. Each step leaves the game playable, its tests green,
> and its probes printing what they printed before.
>
> Inputs: `docs/PERFORMANCE_VS_GODOT_2026-09-11.md` (the baseline numbers). The market scan of
> 2026-09-14 found no Flutter package shipping a GPU voxel world. The closest were a CPU
> `CustomPainter` renderer (`perfectum_3d`) and a heightmap terrain (`macbear_3d`).

## Progress

| Phase | State | Gate |
|:---|:---|:---|
| VP0 Scaffold & baseline | pending — VP0.1 can start now, VP0.2–VP0.3 wait on stage 32's commit | workspace resolves; empty packages analyze clean; baseline logs and parity hashes committed |
| VP1 `voxel_core` by moves | **gate met** 2026-09-14 (VP1.1–VP1.9; VP1.5b pool size pending): 10 source files, 43 package tests, zero Flutter imports; the POC's `world/` keeps only `godot_camera`, `terrain_generator`, `terrain_material` and the `voxel_world` facade | every pure world file imported from `package:voxel_core`; POC tests, parity hashes and probe logs unchanged |
| VP2 `voxel_scene` by moves | pending | no `flutter_scene` import left in the POC's `world/`; radius 8/12/16 within 10% of the baseline |
| VP3 The render gap | in progress (VP3.0 gate fixed; VP3.1 stepped sun: 69 → 84 settle fps at radius 16, gate met) | radius-16 sustained fps above the baseline's 70 (release, 3 workers) |
| VP4 Release prep `0.0.1` | in progress (VP4.1a–c: silent failures throw, API trimmed, every public symbol documented; VP4.2: an example in each package; VP4.3a: `MirroredCamera` in `voxel_scene`; publishing paused by the developer) | `dart pub publish --dry-run` clean for both; a standalone example runs without the POC |

---

## Starting point — `b57cf2a2`, 103 tests green

The blocker of 2026-09-14 20:07 (another session's uncommitted stage 32) cleared with
`03cc989c` (stage 32) and three follow-ups. One of them, `1ea8188c`, matters here. It adds
`world/godot_camera.dart`, the single handedness conversion at the render boundary, and turns
the mesher's winding back to Godot's clockwise order. `godot_camera.dart` stays in the POC for
now. It encodes "a right-handed world on flutter_scene", which `voxel_scene` may want at VP4.1.
Every commit of this plan still stages only its own paths (`git commit -- <paths>`), in case
another session is working in the worktree.

---

## Layout

```
poc_cubeworld/                          the POC app, and the workspace root
  pubspec.yaml                          + workspace: [packages/voxel_core, packages/voxel_scene]
  packages/
    voxel_core/                         pure Dart — no Flutter SDK dependency
      pubspec.yaml                      vector_math, meta; dev: test · version 0.0.0 · publish_to: none
      analysis_options.yaml             strict-casts/inference/raw-types + package:lints/recommended
      lib/voxel_core.dart               the barrel; lib/src/<area>/...
      test/
    voxel_scene/                        Flutter + flutter_scene
      pubspec.yaml                      flutter, flutter_scene: 0.23.0 (exact), voxel_core
      lib/voxel_scene.dart
      shaders/  tool/build_shaders.dart  assets/shaders/terrain.shaderbundle
      test/
```

`voxel_core` declares no `flutter` dependency, so a Flutter import in it fails to resolve
instead of slipping past review. Neither package ever imports `package:cubeworld_poc`.

## What moves, measured at HEAD + the stage 32 worktree

| POC file | Lines | Importers (lib / test) | Destination |
|:---|--:|:--|:---|
| `core/ivec3.dart` | 48 | 23 / 7 | `voxel_core`, as is |
| `world/chunk_mesher.dart` | 820 | 2 / 4 | `voxel_core` (`visibleForTesting` from `package:meta`) |
| `core/blocks.dart` | 454 | 16 / 10 | **split**: `BlockShape`, `CollisionBox`, boxes per shape → `voxel_core`; the 125 `BlockDef` rows and their queries stay in the POC and *build* a core block table |
| `world/chunk_worker.dart` | 168 | 1 / 0 | `voxel_core`, generic over a generator factory |
| `world/voxel_world.dart` | 722 | 18 / 9 | **split** (VP1.6, VP2.2): scheduler, edits, light store → `voxel_core`; nodes, materials, upload budget → `voxel_scene`; the POC's `VoxelWorld` stays as the facade, so its 18 importers do not change |
| `entities/voxel_body.dart` | 217 | 6 / 2 | `voxel_core` without the scene `Node` |
| `player/player.dart:340` `voxelRaycast` (+ `:1970` `liquidRaycast`) | ~45 | — | `voxel_core` free functions; `Player` delegates |
| `world/terrain_material.dart` + `shaders/` + `tool/build_shaders.dart` + bundle | 72 + 57 | 3 / 0 | `voxel_scene` |
| `world/terrain_generator.dart` | 1,308 | 3 / 5 | **stays** (a future `voxel_worldgen`) |
| liquid flow, `Circuits`, dimension rules, save magic | — | — | **stay** in the POC facade |

Four couplings the moves must cut, all found while measuring:

1. **The chunk size is declared three times**: 16×16×128 in `ChunkMesher`, `VoxelWorld` and
   `TerrainGenerator`. It becomes one constant set in `voxel_core`, which the other two read.
2. **The mesher's shape ints duplicate `BlockShape`**: `shapeCube = 0` through
   `shapeRailSlopeW = 24` follow the enum's order exactly. One source replaces both, the enum's
   `index`.
3. **The engine names content**: `VoxelBody.inLava` compares against `'lava'`, and the flow
   checks `'water'`, `'lava'` and `Blocks.has('obsidian')`. In the packages a liquid is an id
   with a kind index from the block table. Named kinds stay in the POC.
4. **The world imports the game**: `voxel_world.dart` builds `Circuits(this)`. The core
   streamer only emits block-changed events, and the POC facade wires circuits to them.

---

## Verification — the same four checks after every step

| Check | Command (from `poc_cubeworld/`) | Passes when |
|:---|:---|:---|
| Analyze | `flutter analyze` (covers `packages/` too — verified in VP0.1) | POC: no errors (stock lints, as today). Packages: zero issues |
| Tests | `flutter test` · `cd packages/voxel_core && dart test` · `cd packages/voxel_scene && flutter test` | all green |
| Parity | `test/voxel_parity_test.dart` (VP0.3) | the hashes committed before VP1 are unchanged |
| Probe logs | `tool/probe_baseline.sh` (VP0.2) re-run and diffed against `docs/baseline/` | identical except the lines carrying `ms` or `fps` |

At the end of VP1.5, VP2.2 and VP3 the performance loop from
`PERFORMANCE_VS_GODOT_2026-09-11.md` also runs: release build, radius 8, 12 and 16.

---

## VP0 — Scaffold & baseline

- **VP0.1** *(can start now: touches only `pubspec.yaml`, `pubspec.lock`, `packages/`,
  `docs/`)* Create both packages empty: pubspecs, analysis options, a barrel and one smoke
  test each. Add `workspace:` to the POC's pubspec with `resolution: workspace` in each
  package. Run `flutter pub get`. Confirm three things in writing below:
  - `flutter analyze` at the root reaches `packages/`;
  - `dart test` works in `voxel_core` under a workspace whose root is a Flutter app (if not,
    the check uses `flutter test` there);
  - the POC still builds and runs.
- **VP0.2** *(after stage 32 lands)* Write `tool/probe_baseline.sh`. It builds the debug app
  and runs `--new --seed=42 --frames=300 --settle=10` with `--stage31`, `--stage32` and a plain
  radius-8 window. Commit the three logs under `docs/baseline/` with the POC SHA they came from.
- **VP0.3** Write `test/voxel_parity_test.dart`, FNV-1a over every array the current code
  produces:
  - `TerrainGenerator(seed: 42)` for the 3×3 ring around (0,0) and (5,−3);
  - `ChunkMesher.build` on both rings, all four surfaces plus the two light volumes;
  - `editsToBytes` of a fixed set of edits.

  The expected hashes are pasted as constants. This test is never edited again until VP3 (VP3
  changes the mesh on purpose and re-pins it).

**Gate:** `flutter pub get` resolves; the four checks pass on untouched code; baseline logs and
hashes are committed.

**VP0 findings (2026-09-14, at `b57cf2a2`):**
- The workspace resolves from the POC root. `flutter pub get` rewrote both packages'
  `analysis_options.yaml` with its platform excludes (kept).
- `flutter analyze` at the root reaches `packages/`: a deliberate unused local in
  `voxel_core/lib` was reported with its `packages/voxel_core/...` path. Both packages
  analyze clean on their own.
- `dart test` under the workspace is proven at VP1.1, the first step with a package test. An
  empty package has nothing to run.
- The POC's 103 tests pass after the workspace change. `voxel_parity_test.dart` pins 48 hashes.
  Nine surfaces are empty in the fixture (hash `0x811c9dc5`): the glow surface in both rings
  and the cutout surface at (5,−3).
- `--stage32` hung once for 9 minutes inside the baseline script and finished in under a minute
  when run alone. The script now gives each probe 240 s and fails loudly.

## VP1 — `voxel_core`, by moves

Each step moves the code, rewrites the POC's imports mechanically, and changes behaviour in
nothing. **API polish waits for VP4**, so a diff here is a move plus the minimum seam.

- **VP1.1** `IVec3` → `voxel_core/lib/src/math/ivec3.dart`. 30 import lines rewritten.
- **VP1.2** Chunk dimensions (`ChunkSize.x/z/y`, `volume`, `index`) plus `BlockShape` and
  `CollisionBox` with the box list per shape → `lib/src/grid/`. `Blocks`, `ChunkMesher`,
  `VoxelWorld` and `TerrainGenerator` read the constants from there.
- **VP1.3** `ChunkMesher`, `ChunkMeshResult`, `MeshSurface` → `lib/src/mesh/`. The shape ints
  become `BlockShape.x.index`.
- **VP1.4** `VoxelBlockTable` → `lib/src/grid/`. Its fields:
  - per id: shape, solid, opaque, emission 0–15, linear rgba, liquid kind index (−1 for none),
    source flag;
  - typed-array views for the isolates (`palette`, `shapes`, `opaque`, `emission`);
  - queries (`isSolid`, `isOpaque`, `collisionBoxes`, `liquidKind`).

  Air is id 0, asserted. The POC's `Blocks` builds one table from its `defs`. `Blocks`' static
  API stays, so its 26 importers do not change.
- **VP1.5** `ChunkWorkerPool` + `WorkerConfig` → `lib/src/streaming/`, generic over
  `abstract interface class ChunkGenerator { Uint8List generate(int cx, int cz, int dimension); }`.
  `WorkerConfig` carries a `ChunkGenerator Function()` built by the POC
  (`() => TerrainGenerator(ids: ids, seed: seed)`) and a `VoxelBlockTable`. A test proves the
  factory crosses `Isolate.spawn`. The pool size stays **3** here, so the perf check measures
  the move alone.
  - **VP1.5b** Default the pool size to `max(1, Platform.numberOfProcessors - 1)`, in its own
    commit, and measure it. The 2026-09-11 run showed radius-16 fill going from 2,981 to
    1,956 ms at 10 isolates.
- **VP1.6** `ChunkStreamer` → `lib/src/streaming/`. It takes the scheduler out of
  `VoxelWorld`:
  - the window with its load and unload radii, the distance-sorted pending list;
  - 3×3 ring readiness, the gen and mesh in-flight sets, `remeshAgain`, the generation epoch;
  - chunk volumes and per-chunk edit deltas, `setBlock` with its remesh-neighbourhood rule;
  - light volumes and `lightAt`, block-changed listeners.

  Finished results go to `abstract interface class ChunkMeshSink { void apply(ChunkPos, ChunkMeshResult); void remove(ChunkPos); }`.
  The POC's `VoxelWorld` keeps its public members, delegates to the streamer, implements the
  sink with the nodes it still owns, and keeps flow, circuits, dimensions and the save magic.
  Unit tests use a fake sink and a flat generator.
- **VP1.7** `EditDeltaCodec` → `lib/src/persistence/`. Magic and version are parameters. The
  POC passes `0x4342574F` and version 2, so existing saves still load byte for byte.
- **VP1.8** `VoxelBody` → `lib/src/physics/`:
  - `late VoxelWorld world` becomes `VoxelQuery` (`int blockAt(x, y, z)`, `VoxelBlockTable table`);
  - the `Node` and `syncNode` leave, into a POC `SceneBody extends VoxelBody` that
    the four subclasses (`Player`, `Mob`, `Boat`, `ItemDrop`) extend;
  - `inWater` and `inLava` become `feetLiquid` / `headLiquid` kind indices; the POC keeps
    `inLava` as a getter.

  The POC's `VoxelWorld` implements `VoxelQuery`.
- **VP1.9** `voxelRaycast` and `liquidRaycast` → `lib/src/physics/raycast.dart`, as free
  functions over `VoxelQuery` with a hit predicate. `RayHit` moves with them.

**Gate:** the four checks; `grep -rn "dart:ui\|package:flutter/" packages/voxel_core` is empty;
the perf loop at VP1.5 lands within 10% of the baseline.

**VP1 log:**

| Step | Commit | Notes |
|:---|:---|:---|
| VP1.1 `IVec3` | `572234fe` | 32 importers rewritten. `--check` showed stage 32's crit count moving (17 → 12): crits roll the game's unseeded `Random`, so `--check` masks that number |
| VP1.2 `ChunkSize`, `BlockShape`, `CollisionBox` | `971e982f` | the three class-level size names stay as aliases of `ChunkSize` |
| VP1.3 `ChunkMesher` | `08c2c599` | **Deviation:** the mesher's `shapeX` ints stay `const`, because `BlockShape.index` is not a constant expression and would sit in the hottest loop. A package test pins all 25 to `BlockShape.index` instead |
| VP1.4 `VoxelBlockTable` | `79554dfb` | `Blocks.table` is built from the 125 rows; liquid kinds indexed by `Blocks.liquidKinds` (water 0, lava 1); the four array getters return the table's arrays, byte-identical |
| VP1.5 `ChunkWorkerPool` | `cc3cc4ce` | `TerrainGenerator implements ChunkGenerator`. The factory is made in a static on `VoxelWorld`: a closure made in an instance method may capture `this` and its unsendable scene nodes |
| VP1.5b pool size | pending | `ChunkWorkerPool.defaultWorkers` = cores − 1 (11 on this 12-core M2 Pro, 8 performance + 4 efficiency); an explicit `workers` still wins. Release loop, 3 → 11 isolates: fill 1243 / 2389 / 3973 → **789 / 1438 / 2467 ms** (−37 / −40 / −38%), fps 116 / 79 / 68 → 120 / 79 / 74, RSS 452 / 717 / 936 → 447 / 776 / 1014 MB (+8% at radius 16: eleven isolates each keep their own 48×48×128 mesher buffers). Against 2026-09-11's Godot at the same radii (766 / 1478 / 2274 ms, at fewer faces then), the Dart fill is now level |
| VP1.8 `VoxelBody` + VP1.9 `VoxelRaycast` | `991c0d41` | one commit: the body and the rays share `VoxelQuery`, which `VoxelWorld` implements. The POC's `SceneBody extends VoxelBody` adds `node`, `syncNode`, `world` typed as the facade, and `inLava` from the liquid kind; `Player`, `Mob`, `Boat` and `ItemDrop` extend it. `inLava`'s string compare became `feetLiquid` / `headLiquid` kind indices. The rays are static (`VoxelRaycast.solid` / `.liquid`): a top-level function named like `Player`'s methods would be shadowed inside the class, and the delegation would recurse |
| VP1.7 `EditDeltaCodec` | `804ff0f0` | the byte layout moves as is; magic, version, dimensions and the accepted legacy version are parameters. Unreadable bytes still decode to null (VD2); the throw waits for VP4.1 |
| VP1.6 `ChunkStreamer` | `05917308` | `VoxelWorld` becomes the facade and the streamer's `ChunkMeshSink`. It keeps nodes, materials, generator, flow, circuits, dimension rules and the save format. `ChunkPos` / `CellLight` move to the package. The pool implements `ChunkJobs`, so the streamer's tests answer jobs synchronously |

**VP1.5 performance gate** (`tool/perf_loop.sh`, release, 3 workers), against `9b722064` built
in a temporary worktree on the same machine. The 2026-09-11 figures are not comparable: stage 32
grew the light pad, and the faces at radius 16 went from 2.17 M to 2.34 M.

| Radius | Fill ms before → after | fps before → after | Peak RSS MB before → after |
|--:|--:|--:|--:|
| 8 | 2127 → 1724 | 114 → 120 | 422 → 442 |
| 12 | 2449 → 2558 | 83 → 90 | 679 → 723 |
| 16 | 3986 → 4044 | 73 → 73 | 878 → 997 |

Fill and fps are within 10%. Peak RSS at radius 16 is 14% higher from one run each side, to be
re-measured at VP2.2 before it is called a regression.

**Found while moving, owed to VP4.1:** an exception inside a worker isolate kills that worker
silently. Its futures never complete, and the world waits on them forever. This is how a package
test with an out-of-range block id showed up as a 30 s timeout. It is the POC's behaviour today,
moved unchanged; the fix is an `onError` port that fails the pending futures.

## VP2 — `voxel_scene`, by moves

- **VP2.1** `TerrainMaterial`, `terrain.frag`, `terrain_cube.frag`, `tool/build_shaders.dart`
  and the bundle → `voxel_scene`. The asset key becomes
  `packages/voxel_scene/assets/shaders/terrain.shaderbundle`. **Risk checked (2026-09-14):**
  `gpu.loadShaderLibraryAsync` is `ShaderLibrary.fromAsset(assetName)` on native, and
  flutter_scene 0.23.0 loads its own engine bundle by the package key
  `packages/flutter_scene/flutter_gpu_shaders/shaderbundles/base.shaderbundle`
  (`lib/src/shaders.dart:12`). So a package asset key resolves. The package lists the
  bundle in its own pubspec, and the POC stops listing `assets/shaders/`.
- **VP2.2** `VoxelChunkView implements ChunkMeshSink`. It holds:
  - the root `Node` and one node per chunk;
  - `MeshGeometry.fromArrays` with light in `texCoords1`;
  - the 7 ms per-frame upload budget;
  - the four materials, `setSkyIntensity`, and the face and chunk counters the probe prints.

  The POC's `VoxelWorld` composes it and loses every `flutter_scene` import except
  `Vector3`.

**Gate:** the four checks; `grep -n flutter_scene lib/src/world/voxel_world.dart` is empty; the
perf loop within 10% of the baseline.

**Gate wording corrected (2026-09-14):** "no `flutter_scene` import in `voxel_world.dart`" was too
strict. The facade exposes `Node get root` to 12 callers (title vista, music, player, remote
players, the stage 30 tests), and that return type is flutter_scene's. What the gate means is
**no rendering code in the POC's world layer**: no `MeshGeometry`, no material constructed, no
shader loaded. The one remaining import serves the `Node` type. The four forwarding material
getters had no caller outside the facade and are removed.

**VP2 performance gate: fill met, fps inconclusive.** A single VP2 run read fill 780 / 1430 /
3232 ms and fps 104 / 89 / 60, far enough from VP1.5b to re-measure. The re-measurement was an
interleaved release A/B on the same machine, in this order: VP2, then VP1.5b (`96a2adf2` in a
temporary worktree), then VP2 again.

| Radius | VP2 first | VP1.5b | VP2 second |
|--:|--:|--:|--:|
| 8 | 872 ms · 120 fps | 1521 ms · 112 fps | 697 ms · 120 fps |
| 12 | 1621 ms · 89 fps | 1475 ms · 89 fps | 1401 ms · 99 fps |
| 16 | 2508 ms · 75 fps | 2447 ms · 83 fps | 2478 ms · 64 fps |

- **Fill at radius 16:** VP2 averages 2493 ms against 2447 ms, +1.9%, which is within the gate.
- **Sustained fps at radius 16:** undecidable with this method. The same VP2 binary read 75 and
  then 64 (−15%), and the last run came after about six minutes of continuous load. A thermal
  and order effect is likely.
- **Why no regression is expected:** VP2 moved node construction and changed an asset key. No
  draw call was added or changed, and the probe logs match the baseline.

The finding that matters: **one run of `perf_loop.sh` carries ±15% on sustained fps**, which is
wider than every 10% gate in this plan. VP3 exists to move fps, so VP3.1 starts by fixing the
measurement (below).

**VP2 log:**

| Step | Notes |
|:---|:---|
| VP2.1 terrain material + shaders | `shaders/`, `assets/shaders/terrain.shaderbundle` and `tool/build_shaders.dart` moved with `git mv` into `packages/voxel_scene`. The package's pubspec lists `assets/shaders/`; the asset key is `packages/voxel_scene/assets/shaders/terrain.shaderbundle`. `title_screen` and `game` call `TerrainMaterial.loadLibrary()` from `package:voxel_scene`. The tool now runs from `packages/voxel_scene` |
| VP2.2 `VoxelChunkView` | the streamer's sink: root node, one node per chunk, the four materials, `setSkyIntensity`. `VoxelWorld` no longer implements `ChunkMeshSink`; it composes the view and forwards `root` and `setSkyIntensity`. Three package tests use all-empty surfaces, so no GPU geometry is created under `flutter test` |

## VP3 — The render gap (measured in the POC, fixed in the packages)

- **VP3.0** Fix the measurement first. One `perf_loop.sh` run carries ±15% on sustained fps (the
  VP2 A/B), and a later run in a sequence reads lower after minutes of load. `perf_loop.sh`
  gains `--repeat N` and `--cooldown S` (a pause between launches). An A/B alternates the two
  binaries A, B, A, B, … rather than running them in blocks, and it reports the median and the
  spread of each. A gate compares medians and is valid only when the difference exceeds both
  spreads. Record the spread of the unchanged binary before trusting any VP3 gain.
  **Built (2026-09-14):** `tool/perf_loop.sh [--repeat N] [--cooldown S] [--radii "8 12 16"]
  LABEL=DIR ...` takes any number of already built POC trees. Each round runs every radius
  for every build and reverses the build order on odd rounds (A,B then B,A), so order and heat
  fall on both sides. Raw rows go to stderr as they finish; the summary gives `median (spread)`
  per build and radius, where spread = max − min. The probe gained
  `[probe] settle fps X over N frames`, the mean over the whole `--settle` window. The old
  `[probe] fps` line is kept, and `probe_baseline.sh --check` filters both.
  **A/A with the old metric (3f1acd9a, the same binary as A and A2, `--repeat 5 --cooldown 20`):**

  | Radius | A fill ms | A2 fill ms | A fps | A2 fps |
  |--:|--:|--:|--:|--:|
  | 8 | 750 (274) | 724 (199) | 120 (10) | 120 (15) |
  | 12 | 1498 (317) | 1477 (159) | 85 (20) | 83 (11) |
  | 16 | 2622 (212) | 2523 (415) | 79 (20) | 68 (16) |

  Cells are median (spread). Fill medians agree within 4%, so fill gates stay valid. The
  last-half-second fps does not: the same binary's radius-16 medians differ by 11 fps (15%) even
  over five runs each, and one run spans 61–81. It cannot gate VP3. The settle-window mean
  replaces it (A/A below).
  **A/A with the settle-window mean (radius 16, the same binary, `--repeat 5 --cooldown 20`):**

  | Build | Fill ms | Last-0.5 s fps | Settle fps | Peak RSS MB |
  |:--|--:|--:|--:|--:|
  | A | 2478 (422) | 68 (8) | 67.1 (7.8) | 1075 (169) |
  | A2 | 2564 (474) | 70 (15) | 66.5 (13.5) | 1012 (152) |

  The settle medians agree within 1% (67.1 against 66.5). Single runs still span 60–74 and look
  bimodal (about 60–61 or 66–74), which points at machine state and not at the metric. **VP3
  gate rule:** five runs per build, alternated; a gain counts when the settle-fps medians differ
  by more than both spreads, about 14 fps (20%) at this noise. Greedy meshing and region batching
  are expected to clear that or be judged not worth it. The baseline for VP3 at radius 16 is
  **67 settle fps** at 3f1acd9a, below the plan's 70 target.
- **VP3.1** Profile before fixing. Take a `--profile` DevTools timeline at radius 16, split into
  UI and raster time, and compare draw calls against vertex count. The ceiling today is 4
  surfaces × 1,225 chunks = 4,900 meshed nodes. Record the numbers here. They pick VP3.2 or
  VP3.3.
  **Prep found (2026-09-14), flutter_scene 0.23.0:**
  - No DevTools needed. A build with `--dart-define=FLUTTER_SCENE_PROFILE=true` prints
    `FLUTTER_SCENE_PROFILE <pass>_mean_us= <pass>_max_us=` per render-graph pass
    (`render/render_graph.dart:339`) and `FLUTTER_SCENE_PROFILE_ENCODER` with sort, encode,
    draws and instances (`scene_encoder.dart:1166`). Draw calls against faces come from there.
  - The depth prepass is off in the POC. It runs only for AO, TAA, SSR, contact shadows, depth
    of field or a material that reads scene depth (`scene.dart:2261`), and the POC uses none.
  - Sun shadows are on: 4 cascades, 2048 px, 110 m (`game.dart:432`). Chunk nodes are
    `shadowStatic` (`voxel_chunk_view.dart:62`), so they render into the shadow cache only when
    coverage or content changes (`scene.dart:2090`), not every frame. Measure with and without
    `--noshadow` anyway, because a moving camera changes coverage.
  - The probe's `fps` is the last 0.5 s window only (`game.dart:571`), so one hitch at the end of
    the run moves it. Part of the ±15% is the metric, not the machine.
  **Measured (2026-09-14, radius 16, release with `FLUTTER_SCENE_PROFILE`, one run each, pass
  times are the engine's means over 120 frames):**

  | Run | ShadowPass ms | ScenePass ms | Encode ms | Draws | Settle fps |
  |:--|--:|--:|--:|--:|--:|
  | shadows, cache on (default) | 7.1–7.3 | 4.3 | 3.4 | 809 | 65.3 |
  | shadows, `--shadowcache=0` | 4.0 | 4.3 | — | — | 75.8 |
  | `--noshadow` | — | 4.4 | 3.4 | 809–819 | 118.8 (vsync) |

  **The render gap is the sun's shadow, not vertices and not draw calls.** Frustum culling
  already brings 4,900 nodes down to about 810 draws, and the scene pass fits in 4.4 ms. Worse,
  the static shadow cache costs 3 ms more than no cache. Cause: `plan()` drops every tile when
  the light direction moves more than 1e-5 (`shadow_cache.dart:106`), and the POC advances the
  sun on every tick (`game.dart` `timeOfDay`, day = 600 s, ≈1.7e-4 rad per frame). So each frame
  re-renders all four cascades, then copies them and walks every item once per cascade for the
  dynamic casters. Fix in the POC: the sun turns in 0.5° steps (`--sunstep=`, 0 = smooth), so
  the cache holds for about 0.8 s of game time between rebuilds. VP3.2 and VP3.3 wait until
  this is measured.
  **Gate A/B, cache on against `--shadowcache=0` (a67e9a28 binary, radius 16, 5 alternated runs):**
  settle fps 76 (9) against 82.1 (7.4). The 6 fps gap is inside both spreads, so by the VP3.0 rule
  it is not proven, though it points the same way as the pass times. The same cache-on binary read
  67 in the VP3.0 A/A an hour earlier: absolute numbers drift between sessions, so only builds
  measured in the same alternated run may be compared.
  **Gate A/B, stepped sun (one binary, radius 16, 5 alternated rounds of three configs):**

  | Config | Fill ms | Settle fps | Runs (settle fps) |
  |:--|--:|--:|:--|
  | `step` (default, 0.5°) | 2503 (397) | **83.6 (5.5)** | 87.3 · 86.9 · 82.7 · 81.8 · 83.6 |
  | `smooth` (`--sunstep=0`, the old behaviour) | 2590 (127) | 69.1 (11.3) | 62.2 · 69.1 · 69.1 · 73.3 · 73.5 |
  | `nocache` (`--sunstep=0 --shadowcache=0`) | 2553 (213) | 77.4 (13.6) | 73.2 · 86.8 · 77.1 · 83.2 · 77.4 |

  **Gate passed.** Stepped against smooth is +14.5 fps (+21%), more than both spreads, and every
  stepped run beats every smooth run. Radius-16 settle fps is above the 70 target. Fill is
  unchanged (inside spreads), and tests, parity hashes and probe logs are unchanged. A stepped sun
  also beats no cache at all, so the static cache now pays for itself.
  **Profile with the stepped sun (same run shape as the table above):** ShadowPass mean 0.63–0.78 ms
  (was 7.1), max 6.2–7.7 ms on the frame a step rebuilds the four cascades; ScenePass 4.4–4.7 ms;
  one run read 88.7 settle fps.
  **What this leaves for VP3.2 / VP3.3.** The scene pass is now the largest per-frame cost, and
  3.4 ms of it is encoding about 810 draws. That is region batching's target (VP3.3: fewer, larger
  nodes → fewer draws), not greedy meshing's (VP3.2: fewer vertices per draw). A second, smaller
  item: the rebuild spike of about 7 ms every 0.8 s of game time. flutter_scene would refresh one
  stale tile per frame if only the signature changed (`maxAmortizedRefreshes`), but a light
  direction change rebuilds all four at once. Record it before deciding whether a 1–2 frame hitch
  at that rate matters.
- **VP3.2** If vertex cost dominates, use greedy meshing. **Known blocker:** `_noise`
  multiplies every voxel's colour by a positional hash (±7%), so no two neighbouring faces share
  a colour and nothing can merge. Move the jitter into the terrain shader first, as a hash of
  the world cell. Then merge only quads with equal colour, AO and light. Re-pin the parity
  hashes in the same commit.
  **Prep found (2026-09-14):**
  - The path for the jitter exists. flutter_scene's `material_varyings.glsl` gives every
    material shader `GetWorldPosition()` and `GetWorldNormal()`. The voxel a fragment belongs to
    is `floor(position - normal * 0.5)`, and `_noise`'s hash (`chunk_mesher.dart:410`, u32 xor
    and multiply) ports to GLSL ES 3.0 `uint` math.
  - `terrain.frag` already multiplies `v_color` into the albedo, so the mesher keeps block tint ×
    face tint × AO in the vertex colour and the shader adds the jitter.
  - The second limit on merging stays: AO is per vertex and light per face (`texCoords1`). A
    greedy quad can only join faces with the same colour, the same AO on all four corners and
    the same light. Measure the merge rate on the parity fixture before building it.
- **VP3.3** If draw calls dominate, batch chunks into regions: one node per surface per 4×4
  chunks, remeshed when one of its chunks changes.

**Gate:** radius-16 sustained fps above 70 in the release POC, recorded beside the
2026-09-11 table.

## VP4 — Release prep `0.0.1`

- **VP4.1** API review: public names, docs on every public symbol, nullable-return fallbacks
  removed (`IVec3.parse` returning null becomes a throw), barrel exports trimmed to intent.
  The POC follows in the same commits.
- **VP4.2** A standalone `example/` in each package with a small built-in generator, so the
  release runs without the POC. `voxel_scene`'s example is macOS, with `FLTEnableFlutterGPU`
  and **no app-level `hook/build.dart`** (the POC's hooks_runner gotcha).
- **VP4.3** README per package, `CHANGELOG.md` with a single `0.0.1` entry, LICENSE (`VD6`),
  `dart pub publish --dry-run` clean.
- **VP4.4** Export: copy both packages into a new repository as one commit. The POC may then
  consume them from that repository or stay on the workspace copy (developer's call then).

**VP4 log:**

| Step | Notes |
|:---|:---|
| VP4.1a the three silent failures | **Worker pool:** each job runs in a `try` on its worker and a throw comes back as a `RemoteError` with the worker's stack; the worker keeps serving. Workers spawn paused with error and exit listeners, so a generator factory that throws makes `start()` throw instead of waiting forever, and a worker that dies later fails only its own jobs (`StateError`) and leaves the pool. `dispose` fails what is left with the new `ChunkJobCancelled`. **Streamer:** it used to swallow every job error. It now ignores `ChunkJobCancelled` and rethrows any other from the next `update()`; the failed chunk is dispatched again. **`EditDeltaCodec.decode`** throws `FormatException` for another magic, an unknown version, a cut-short file or bytes left over (a cut file used to throw `RangeError` from `ByteData`). **`IVec3.parse`** throws `FormatException`. The POC follows: `loadEditsFromBytes` returns `int`, and the save loader and net handlers lose their null checks, so a corrupt save or message now fails loudly. Checks clean (voxel_core 48 tests, POC 104, voxel_scene 3). **Flake seen:** the first `probe_baseline.sh --check` differed on stage 31's camera line in the third decimal (9.050 against 9.052); the rerun matched. The camera line is frame-time dependent, and `--check` does not filter it |
| VP4.1b the API trimmed to intent | Behaviour unchanged, parity hashes unchanged. **`ChunkMesher`:** the 25 shape ints, the three size aliases, `pad` and `index` go private (callers use `ChunkSize.index`); a `@visibleForTesting shapeIndices` list keeps the pin test. `build` takes `List<Uint8List?> ring` (the chunk, then its eight neighbours in `ChunkStreamer.ring` order, as `ChunkJobs.mesh` already did) instead of eleven positional volumes, and throws on a ring that is not nine or has no chunk; a chunk meshed alone is `[chunk, ...ChunkMesher.noNeighbours]`. **`WorkerConfig`** → `ChunkWorkerConfig`: the old name was too broad for a package export. **`ChunkStreamer`:** `chunksBuilt`, `facesEmitted`, `meshMsTotal` and `remeshesQueued` become read-only getters. **`VoxelBody`:** `removed` is gameplay and moves to the POC's `SceneBody`; `inWater` / `headInWater` become `inLiquid` / `headInLiquid` (they were true in lava too); `gravity` and `waterGravity` become instance fields `gravity` and `liquidGravity`, so a game can tune them. Docs on every public symbol follow in VP4.1c. **Flake seen:** the first `--check` run hit the 240 s alarm on stage 31; the same probe run by hand finished in normal time with no exception, and the rerun matched |
| VP4.1c docs on every public symbol | Both packages turn on `public_member_api_docs`; its 186 findings (177 core, 9 scene) are now zero, and the lint keeps it so. The docs lost their POC history: no stage numbers, no Godot, no `VoxelWorld`, no probe flags. What a caller could not learn before is now written down: `MeshSurface`'s layout (chunk-local positions, four rgba floats of tint × AO, two light floats for a second UV set, six indices a quad) and **its clockwise winding**, which a counter-clockwise renderer must mirror at the camera; the mesher's static buffers (one build per isolate at a time); `VoxelBlockTable`'s throws; `rayDistance`'s −1 miss. Comments only: analyze, the three test suites and the parity hashes are clean; the probe logs were not rerun for a comments-only diff |
| VP4.2 an example in each package | **`voxel_core/example/voxel_core_example.dart`** (`dart run`, no pubspec of its own): a six-block table and a sine-hills `ChunkGenerator` made by a top-level factory; a `ChunkWorkerPool` streams radius 3 into a counting sink (49 chunks on 11 workers in ~0.6 s), then a `VoxelRaycast` down, a lamp placed through `setBlock` (9 remeshes, block light 14 beside it), an `EditDeltaCodec` round trip (45 bytes) and a `VoxelBody` dropped onto the ground. **`voxel_scene/example/`**: a macOS app (`flutter create`, App Sandbox left on — the pool's isolates run in it) with `FLTEnableFlutterGPU` in `Info.plist` and no `hook/build.dart`; the same hills with a lake and lamps at radius 6 under a shadowed sun, an orbiting camera and a stats line. It is a workspace member (`resolution: workspace`), so the release repository's root is a workspace too (VP4.4). Verified by an uncommitted in-app `RepaintBoundary` capture, the screen being locked: 169 chunks drawn, faces culled the right way. **Found:** a `voxel_scene` user must mirror clip-space x (the meshes wind clockwise) and draw front faces in the shadow pass; the example carries a 20-line `MirroredCamera`, the POC its `GodotCamera`. Whether that camera belongs in `voxel_scene` is decided at VP4.3. Checks clean (analyze, voxel_core 51 tests, voxel_scene 3, POC 104); the POC is untouched, so the probe logs were not rerun |
| VP4.3a the mirrored camera ships in `voxel_scene` | Decided: yes, because every `voxel_scene` user needs it and a world seen mirrored gives no hint why. **`MirroredCamera`** (`PerspectiveCamera` with `MirroredProjection`, clip-space x negated, still a `PerspectiveProjection` for the shadow cascades) carries `shadowCasterFaces = ShadowCasterFaces.front` and the `primitive` / `primitiveNode` helpers for engine-wound geometry. The POC's `GodotCamera` now extends it and forwards the two statics (Dart does not inherit them), so no caller changed; the example drops its own copy. Three tests pin it in the package: +X on screen-right with depth untouched, the lens type and caster faces, and the primitive's mirrored child (a mesh without primitives, so no GPU). **Paused:** the developer set publishing aside (2026-09-15), so the READMEs, CHANGELOG, LICENSE, the dry run and VP4.4 wait. Checks clean (analyze, voxel_scene 6 tests, POC 115 — the other session's stage 33 added tests); the example builds for macOS. Behaviour is unchanged, so neither the probe logs nor an in-app capture were rerun |

---

## Decision register

| ID | Question | Recommendation | Why |
|:---|:---|:---|:---|
| `VD1` | Packages under `poc_cubeworld/packages/` with the POC as workspace root, or at the worktree root? | **Under the POC** | The worktree root is the frozen 2D app with `flame`. Rooting the workspace in the POC keeps that app and its lockfile out of it |
| `VD2` | Move then polish, or design the final API while moving? | **Move then polish (VP4)** | A move with identical hashes is provable; a redesign mid-move is not. The POC stays playable at every commit |
| `VD3` | Package lint level | **strict-casts / inference / raw-types + `package:lints/recommended`, zero issues** | A published package is judged by pub.dev's analysis. The POC keeps its stock lints |
| `VD4` | `flutter_scene` pin | **Exact `0.23.0`** | `TerrainMaterial` imports the private `package:flutter_scene/src/gpu/gpu.dart`, which may move in any release |
| `VD5` | Web in `0.0.1`? | **No** | `dart:isolate` has no web implementation; the pool would need a web-worker twin, and the WebGL2 path is unmeasured |
| `VD6` | License for `0.0.1` | **MIT, decided at VP4.3** | Matches `flutter_scene`, and it is what the Flutter 3D packages found in the scan use |
| `VD7` | Terrain generator, liquid flow, circuits in `0.0.1`? | **No, they stay in the POC** | Their rules are content (biomes, named liquids, redstone); they become `voxel_worldgen` or similar after `0.0.1` |
