# Changelog

## Unreleased

- **Breaking: `VoxelChunkView` draws what changed in `rebuild`, once a frame, within a
  time budget.** `apply` and `remove` only keep or drop the chunk and mark its region;
  `rebuild(near, {budgetUsec})` builds the marked regions nearest the chunk `near` first,
  each once however many of its chunks changed, while the next one's cost, predicted from
  its vertices by the rates measured so far, fits in `rebuildBudgetUsec` (2 ms); the rest
  wait for the next call, and the first region of a call is always built. A region left
  with no chunk drops its node in the same call. A chunk's lit surfaces are packed the
  first time a rebuild reads them, still once. Before, every apply and removal rebuilt its
  region at once: the column of chunks a streamer hands over together, and the one that
  leaves the window, cost one long frame, and a region was rebuilt with each of its chunks
  in turn. `pendingRegions` counts the regions waiting. A game that drives the view
  itself must call `rebuild` every frame, or nothing is drawn.
- `RigPart.apply` and `NodeBody`'s drawn pose write their node's matrix in one
  `mutateLocalTransform`, from a pose shared by every part and body, and allocate nothing:
  before, each part every step built a quaternion and two vectors and went through the
  node's `rotation` and `scale` setters, each of which rebuilt the matrix as a new one.
- **Breaking: `SelectionOutline` is one mesh, drawn in one draw.** Its twelve sticks were
  twelve nodes (24 with their mirrors), a `CuboidGeometry` each, so twelve draws, and
  twelve draws are ~0.3 ms of a phone's colour pass; they are now one `BoxMesh` on the
  outline's `node`, built the first time a box of that size is shown and kept by size, and
  `show` moves the node and swaps the mesh only when the size changes. The layout is
  `stickBoxes(box)` (the twelve boxes, relative to the box's minimum corner), which
  replaces `stickTransforms` (a position and a scale for each of twelve cubes); `gap`,
  `thickness`, `depthBias` and the look are unchanged.
- `BoxMesh` (new): boxes (`Aabb3`) as flat arrays, `arrays`, or one `MeshGeometry`,
  `geometry`, six faces a box, wound as the chunk mesher winds, so the mesh is drawn
  through a `MirroredCamera` on a plain node: one draw for them all.

## 0.2.0-dev

- `NodeBody` keeps two poses of its node, the last step's and the one before it, each a
  position, a yaw and a pitch, and draws the node between them: `syncNode({at, yaw,
  pitch, snap})` sets the step's pose and puts the node there (as before, and now turned
  too), `beginStep()` makes it the pose the frames draw from, and `drawNode(alpha)` puts
  the node `alpha` of the way from the one to the other, the yaw the short way round;
  `drawnPosition` is where it stands. A body's first sync, and one with `snap`, jumps. A
  game that never calls `drawNode` sees the node where the last sync put it. The node's
  transform is written whole (translation and rotation, scale 1).
- `VoxelChunkView` packs a chunk's lit surfaces once, when its mesh arrives, and keeps
  them packed: a region's rebuild moves each chunk's words by an integer offset instead
  of packing every chunk's floats again, on the UI thread, at every mesh in the region.
  The bits are the same as before (`PackedSurface.of` packs one chunk, `merge` moves and
  joins them), and the view no longer keeps the lit surfaces' floats.
- The terrain's lit surfaces (solid, cutout, liquid) draw in a packed 16-byte vertex
  where the engine's is 72: a `Geometry` of the kit's with its own vertex shaders
  (`shaders/terrain.vert`, and `terrain_depth.vert` for the shadow cascades, the depth
  prepass and the selection mask), two streams of two 32-bit words. The position is in
  1/256 m from the region's corner, which the depth passes read alone (8 bytes a vertex
  where they read 12); the colour's square root, the normal and the two light levels
  are the second. The glow surface keeps the engine's vertex: its baked colour can pass
  1.0. The terrain looks as it did: against the 72-byte vertex, 0.04% of a frame's
  pixels differ by more than 2 of 255, fewer than between two runs of the same build.
  `VoxelChunkView` asserts `regionChunks` × the chunk size stays under 256 m, and
  `TerrainMaterial.loadLibrary` now requires the bundle's two vertex shaders; the
  bundle is rebuilt, and `tool/build_shaders.dart` compiles vertex shaders too.
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
