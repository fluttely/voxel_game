# Changelog

## Unreleased

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
