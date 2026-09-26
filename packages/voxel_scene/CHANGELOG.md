# Changelog

## Unreleased

- The terrain shader multiplies in each block's colour variation, computed from the
  fragment's cell with the same hash as voxel_engine's `ChunkMesher.voxelTint`, which the
  mesher no longer bakes into the vertex colour so it can merge faces. The terrain
  looks as it did: against the baked variation, 97.7% of a frame's pixels are identical
  and the rest lie on cells' edges, where multisampling now shades one cell's variation.
  Requires voxel_engine's greedy mesher; the shader bundle is rebuilt.
- `VoxelChunkView` draws chunks in regions of `regionChunks` × `regionChunks` (2 by
  default): one node per region, one geometry per surface in it, the chunks' offsets
  baked into its positions and its bounds taken while they are copied. flutter_scene
  batches only draws of the identical geometry, so every chunk surface was a draw of
  its own in every pass; at radius 6 the colour pass draws ~40 items where it drew ~95.
  A chunk's mesh or removal rebuilds its region from the surfaces the view now keeps.
  **Breaking:** `nodeCount` is gone; `chunkCount` and `regionCount` replace it, and a
  node is named `region_x_z` where it was `chunk_x_z`.

## 0.1.2-dev

- Formatted by `dart format` at the 120 columns the code is written at
  (`formatter: page_width: 120` in `analysis_options.yaml`); pana took 10 pub points
  for formatting.

## 0.1.1-dev

- Requires Flutter 3.47.1, the first with a runner setting that turns Flutter GPU on for
  Windows and Linux. The README says how on every platform, and why the web is not one.
- `DayNightSky` takes the shadows' `shadowCascades`, `shadowResolution` and
  `shadowDistance` (4, 2048 and 110 m, as they were fixed before).
- `DayNightSky`'s fog is Minecraft's band: linear, `DayNightSky.fogBand` metres
  wide (a tenth of the edge, 4 to 64) and full on the edge. It used to start at
  45% of the distance and hazed a good part of the loaded world.

## 0.1.0-dev

First version.

- `VoxelChunkView`: `voxel_engine` chunk meshes as flutter_scene nodes.
- `TerrainMaterial` with its compiled shader bundle.
- `MirroredCamera` for the engine's winding, and shadows that match.
- `DayNightSky`, `SelectionOutline`, `VoxelModelMesh`, `RigPart`, `NodeBody`.
