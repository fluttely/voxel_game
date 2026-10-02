# Changelog

## 0.3.0-dev

- `Biome.precipitation` (a `Precipitation`, new: `rain`, the default, `snow` or `none`):
  what falls on a biome when the weather turns (VA9). The generator does not read it.

- `Inventory.put(stack)` (new): a new stack tops up stacks as `add` does, a worn or
  bonused one takes an empty slot whole as `addStack` does; returns what did not fit.
- What an item looks like (VA5): `ItemType.shape` (an `ItemShape`, new, null by default)
  and `ItemModel.of(item, blocks, items)` (new), its voxels built once a look — two items
  that look alike are one model, so a renderer makes one mesh or icon for both. A shape is
  one of the kit's (`ItemShape.block`, the item's block as the mesher draws it: a cube, a
  slab, stairs, a torch, a sprout, a flower, a door, a fence, a ladder, a wire, a rail;
  `pickaxe`, `axe`, `shovel`, `hoe`, `sword`, `bow`, `lump`, `gem`, `cap`, `tunic`, `pail`,
  the `StockItemShape`s, painted in the item's colours; a full pail is the empty one's
  colour with its liquid's in it) or a `CustomItemShape` of the game's own boxes of
  voxels. An item that declares none takes one from its row (`ItemModel.shapeOf`): a
  block's item its block, a tool of the five stock kinds its kind, food a lump, armour a
  tunic, a bucket a pail, anything else a gem; a tool of any other kind throws
  `ArgumentError` and must declare its shape. Each model says how it is held
  (`ItemGrip`, new: `block` against the palm, `flat` or `upright` out of the fist), where
  (`origin`), at what size (`scale`, `ItemShape.voxelSize` for the stock ones) and its
  `bounds`.
- `ItemType.bucket` (a `Bucket`, new): `Bucket.empty` names, per liquid kind, the full item
  it becomes once it scoops that liquid's source; `Bucket.full` names the source block it
  pours and the item it becomes once poured (VA2).
- `BlockType` says what a block does on its own (VA2), all off by default: `falls` (sand,
  gravel), `support` (a `Support`, new: `Support.below`, on any solid block or on the ones
  named in `on`, or `Support.side`, an opaque block on one of the four sides), `onWall` (the
  block placed instead against a wall: a torch's wall torch) and `loot` (a `LootTable`
  rolled for its drops instead of `drop`), `facing` (a `Facing`, new: `Facing.compass`,
  four variants by the side the placer looks toward, or `Facing.axis`, two by the axis they
  look along), `tall` (two cells, both halves this block), `usedInto` (the block a use
  turns it into: a door opens, its open state closes), `grows` (a `Growth`, new: the next
  stage of a crop, the seconds of light it takes and the least light it grows in) and
  `turnsWith` (tool kind to the block that tool turns it into: a hoe tills) and `storage`
  (a `Storage`, new: the slots a chest holds and the `LootTable` a generated one is found
  with). `BlockRegistry.stands` answers
  whether a block would stay at a cell, and the registry refuses a row naming a block that
  does not exist.
- `ItemType.food` (a `Food`: hunger it fills, health it gives back, an effect it starts for
  some seconds at some power, an item it leaves behind) and `ItemType.armor` (an `Armor`: the
  slot it is worn in and the points it is worth), both new, both null for an item that is
  neither eaten nor worn. The comment that told a game to subclass `ItemType` for food and
  armour is gone: they are fields now, so the kit's player reads them from any game's rows.

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
