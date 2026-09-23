# Changelog

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
