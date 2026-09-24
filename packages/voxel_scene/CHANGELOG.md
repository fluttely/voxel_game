# Changelog

## Unreleased

- `DayNightSky`'s fog is Minecraft's band: linear, `DayNightSky.fogBand` metres
  wide (a tenth of the edge, 4 to 64) and full on the edge. It used to start at
  45% of the distance and hazed a good part of the loaded world.

## 0.1.0-dev

First version.

- `VoxelChunkView`: `voxel_engine` chunk meshes as flutter_scene nodes.
- `TerrainMaterial` with its compiled shader bundle.
- `MirroredCamera` for the engine's winding, and shadows that match.
- `DayNightSky`, `SelectionOutline`, `VoxelModelMesh`, `RigPart`, `NodeBody`.
