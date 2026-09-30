# Changelog

## 0.3.0-dev

- `ChunkStreamer.putChunk` stores a volume generated elsewhere (a test's floor), with the
  edits recorded for it written over it, as a generation landing would. Since 0.2.0-dev
  made `chunks` read-only it was the one way in that was missing: a world built without
  jobs had nowhere to put its chunks.
- `ChunkWorkerPool.defaultWorkers` is two thirds of the cores (`workersFor`, new), no
  longer all of them but one: 8 on an M2 Pro instead of 11, 5 on a Galaxy S24 instead of
  7. Past that the window's fill time did not fall (on the phone 735 ms with 5 workers,
  728 with 7), each job ran slower (a mesh 10.6 ms at 4 workers, 15.8 at 7), and the extra
  isolates took the cores the UI and raster threads need.
- `ChunkStreamer` sends a chunk's mesh job when the last generation of its ring lands,
  no longer at the next `update`: the window's fill was 387 → 350 ms in a prototype
  (M2 Pro, radius 6), and the ring's copy leaves the frame for the message handler. Only
  the nine chunks around the one that landed are looked at, so jobs that answer at once
  (a headless world's) still fill over several updates.
- `ChunkMesher.build` no longer allocates on every cell of its loop: the ladder, the
  rails and the fence drew with closures declared in the loop's body, which captured the
  cell's variables, so Dart allocated a context for them on every one of a chunk's 32768
  cells (and boxed the cell's coordinates into it), whatever the cell held. They are
  methods now; the meshes are the same, vertex for vertex.
- `ChunkMesher` keeps the four surfaces it fills from one `build` to the next: each
  build allocated 4 × 216 KB of growable arrays, and again each time one doubled, all of
  it garbage once the result was copied out. A result's arrays are exact-size copies
  now, which outlive the next build as before.
- `ChunkMesher.buildWith` (new) meshes like `build` and hands the result to a callback,
  its arrays the mesher's own and valid only inside it. `ChunkWorkerPool`'s workers use
  it: they copy the mesh into transferables anyway, so the exact-size copies `build` makes
  (~0.3 MB for a chunk of the example's hills, and 64 KB of light) are no longer made.
- `eulerYXZInto` (new) writes `eulerYXZ`'s rotation into a quaternion it is given, the
  product of the three axis rotations worked out by hand; `eulerYXZ` is built on it. A
  rig part posed every step no longer allocates eight vectors and quaternions for it.
- `NetHost.broadcast` encodes its message once for every peer, no longer once per peer,
  and each send is one write, no longer two (`writeln` wrote the line, then the newline):
  a host's 20 Hz state of 40 creatures cost it 369 µs with 4 peers and 797 with 8 (M2
  Pro), against 106 and 122 now. `EncodedMessage` (new) is a message encoded once;
  `NetConnection.sendEncoded` (new) sends one to a connection.
- A `NetConnection` whose peer hangs up while a write is in flight closes (`done`
  completes, and a `NetHost` drops the peer through `onLeave`), where the write's
  `SocketException` (`Broken pipe`) used to reach the zone unhandled, which ends a plain
  Dart process. A message sent that way is lost, as it was.

## 0.2.0-dev

- `ChunkMesher` merges cube and liquid faces greedily: coplanar neighbours of the same
  block, light, AO corners and lowered top become one quad, across a direction only
  where the AO does not change along it, so the interpolated colour is what the unit
  faces had. The kit example's radius-6 window meshes 114,193 faces where it meshed
  185,130 (solid −31%, liquid −98.5%). **Breaking:** the per-block colour variation is
  no longer in `MeshSurface.colors` (it made every face different); a renderer computes
  it from the cell with the new `ChunkMesher.voxelTint`, as voxel_scene's terrain shader
  does. The `glow` surface, meant for an unlit material, keeps it baked and unmerged.

## 0.1.2-dev

- Formatted by `dart format` at the 120 columns the code is written at
  (`formatter: page_width: 120` in `analysis_options.yaml`); pana took 10 pub points
  for formatting.
- `Pathfinder.find` keys its cells by an int (the offset from the start, packed) and
  keeps its nodes in lists reused from one search to the next, allocating nothing per
  cell it opens; the paths are the same, the search about 1.6 times faster. A `PathCosts`
  callback that searches again throws a `StateError`. With 40 creatures (`mobs:6`, M2 Pro)
  a step's p99 goes from 8.7 ms to 4.7.
- `ChunkStreamer.getBlockXYZ` and `lightAt` find a chunk by shifts and an int key
  (`ChunkStreamer.keyOf`) instead of a double division and a record key: 41 → 14.5 ns
  and 66 → 32 ns a call. `ChunkStreamer.chunkAtXZ` returns a column's volume the same
  way. `ChunkSize` gains `shiftX`/`shiftZ` and `maskX`/`maskZ`.
- `ChunkStreamer.chunks` is read-only (an `UnmodifiableMapView`): the streamer keeps it in
  step with the int-keyed copy its queries read.

## 0.1.1-dev

- No code change. The README says why the web is not a target: streaming spawns
  isolates and `net.dart` is TCP sockets, through `dart:isolate` and `dart:io`.

## 0.1.0-dev

First version. It is the five pure-Dart packages that came
before it — `voxel_core`, `voxel_worldgen`, `voxel_content`, `voxel_signals`
and `voxel_net` — merged into one package with a library per subject. No code
changed in the move; `package:voxel_core/voxel_core.dart` became
`package:voxel_engine/core.dart`, and so on for the other four.

- `core.dart`: `VoxelBlockTable`, `ChunkGenerator`, `ChunkWorkerPool`,
  `ChunkStreamer`, `ChunkMesher` with light and ambient occlusion, `VoxelBody`,
  `VoxelRaycast`, `Reach`, `LiquidFlow`, `Pathfinder`, `VoxelModel`,
  `EditDeltaCodec`.
- `worldgen.dart`: `WorldGenSpec` compiling to a `ChunkGenerator` — biomes by
  climate, terrain recipes, caves, ores, trees, plants, structures, and
  `FastNoiseLite`.
- `content.dart`: `BlockRegistry`, `ItemRegistry`, `MiningRules`, `Inventory`,
  `RecipeBook`, `LootTable`, `StatusEffects`.
- `signals.dart`: `SignalNetwork` and `SignalRules` for wires, levers, lamps,
  doors and pistons; `RailGraph` for rails that lay themselves.
- `net.dart`: `NetHost`, `NetConnection` and `connectToHost` over TCP.
- `voxel_engine.dart` exports all five.
- A sixth example, `voxel_engine_example.dart`, runs the subjects together.
- Dartdoc describes the behaviour in its own words instead of by reference to another
  game (`ItemType.tier`, `VoxelModel`, `VoxelBody.wading`).
