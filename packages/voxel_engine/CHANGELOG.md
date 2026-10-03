# Changelog

## 0.3.0-dev

- `ChunkMesher.liquidTop` (new, 0.875): how high a liquid's top is drawn in a cell with no
  liquid of its own above, what a game reads to tell an eye over a pool's surface from one
  under it (VA-Zf).
- Minecraft's world, as rows (VA-Ze).
  - `Biome.flats` (new) of `Flats` (new: `height` 2, `keep` 0.3, `reach` 9, the app's swamp):
    a column standing from one to `reach` blocks over the sea is pressed toward `height`
    over it, wherever the biome declaring it is the one the column would then grow (so a
    desert tried first keeps its ground). Only a land biome's; a cavern's or a shore's throws.
  - `WorldGenSpec.shores` (new): biomes tried in order on the beach's columns, the first
    whose climate holds taking it, else the beach. A cold one with `ice` is a frozen shore.
    `WorldGenSpec.allBiomes` (new) lists the land's, the shores, the ocean and the beach.
  - `Temple` (new, stock): a step pyramid of `stone`, 9 x 9 and five steps, over a 3 x 3 x 3
    chamber reached from the south, two `chest`s, a `light`, a `plate` on a `trap`; every
    furnishing nullable. (The app's fortress stays its own `CustomStructure`: its layout is
    read by its boss, VA-Zl.)
  - `SpecGenerator.structureNamed` (new).
  A spec using none of them generates what it did.

- Minecraft's items, declared as rows (VA-Zd); the engine only declares them, the kit's
  player does what they say.
  - `ItemType.launcher` (new) of `Launcher` (new: the `shot` by name, the `ammo` item a shot
    spends or none, a `cooldown`, 0.5 s): an item that shoots. `ItemModel.shapeOf` draws one
    as a bow.
  - `ItemType.light` (new, 0..15): the light an item gives in hand; `ItemRegistry.forBlocks`
    gives a block's item its block's.
  - `Food.cures` (new): eating it ends every bad effect. `StatusEffects.hasBad` (new).
  - `MiningRules.cuts` (new, tool kind → block tags) and `MiningRules.cut` (new): a tool
    that cuts a block takes it at once (`mineTime` 0.05), and `drops` is true for it.
  - `BlockType.bed` (new): a bed. `BlockType.holdable` (new, true; false for a liquid): a
    block only the world makes (a portal, an open door, a rail's curve) is no item, and
    `ItemRegistry.forBlocks` leaves it out.
  - `ItemShape.shears` (new, a stock shape), and a tool of kind `shears` takes it.

- `ItemType.glider` (new) of `Glider` (new: `speed`, `fall`, `steer`, a hang glider's by
  default): an item that glides, carried in the bag. The engine only declares it; the kit's
  player glides with it (`VoxelAction.glide`).

- `Inventory.roomForStack` (new): how many of a stack `put` would take — a new one as many as
  `roomFor`, a worn or bonused one all or nothing. A host reads it of a peer's declared bag
  before it hands a drop over.

- `SignalRules.usedInto` (new): what a use turns a block into (a lever flipped, a button
  pressed), null for neither; `SignalNetwork.use` writes it. A client, which runs no circuits,
  reads it to flip a lever as a block edit of its own that the host's circuits answer.

- `LootTable.oneOf` (new): a table that gives one of its entries or nothing — each entry's
  chance is its slice of one roll, in order, and what the slices leave gives nothing (a
  fishing line's catch: 70 % fish, 10 % salmon, ...). `LootTable.check` (new) throws for
  slices that sum over 1, and `roll` checks them; `LootTable.oneOf` (the flag) tells the
  two kinds apart. A table built as before rolls each entry by its own chance, unchanged.

- A richer world, declared as rows (VA11). A spec that uses none of them generates what it
  did before, chunk for chunk (`spec_test.dart` pins it).
  - `WorldGenSpec.strata` (new) of `Stratum(block, belowY:)` (new): the rock below a height
    is that block instead of `stone` (dark stone in the deep); ores vein it as they vein
    stone, in a cavern too.
  - `Biome.covers` (new) of `Cover(block, perMille:, minHeight:, maxHeight:, patch:)` (new):
    the surface block where the ground stands in a window of height and a roll hits, one
    roll per `patch` square, tried in order — snow on the peaks, gravel on the sea floor,
    patches of mud. A cavern's floors take them too.
  - `Biome.pools` (new, a `Pools(bed:, threshold:, scale:)`): one block of the world's water
    over `bed` where noise runs high on land above the sea, never beside lower ground or
    over a cave, so the water stays put. Nothing grows in a pool.
  - `TreeSpec.weight` (new, 1): a biome picks its trees by weight. `TreeSpec.belowY` (new):
    a tree grows only on ground below it. `TreeSpec.oak`/`spruce`/`palm` take both.
  - `Plant.maxHeight` (new; `height` when null): a plant stands `height` to `maxHeight`
    tall (a cactus, two or three). `Plant.spread` (new, 0..4): that many neighbours (+x, +z,
    -x, -z) level with it may grow one too, each on a coin — a patch of melons, whole across
    chunk borders. `Plant.byWater` (new): it grows only beside water at the surface (the
    sea, a river, a pool), and a column away from water skips it without spending its
    share (reeds). A cavern throws `ArgumentError` for pools, spreading and water-seeking
    plants.
  - **Breaking:** `StructureSpec(name, structure, regionChunks:, chance:, biomes:)` takes a
    `Structure` (new): how far it reaches (`radius`), how deep it sits (`depth`), how far
    trees stay off (`clearing`), its `blockNames` and `build(site)`. A build function is a
    `CustomStructure(build, radius:, depth:, blocks:)` (was `StructureSpec(name, build:,
    radius:, depth:)`); `StructureBuild` moved to `structure.dart`. A structure's blocks are
    in `WorldGenSpec.blockNames`, so a world fails to compile naming a missing one.
  - The stock structures (new), every block taken by name, the furnishings nullable:
    `Dungeon` (three rooms under the ground, guarded, a ladder shaft up), `Tower`, `Well`,
    `Camp`, `Ruins`, `Mine` (a head frame, a ladder down to a corridor at `floorY` with
    supports, lights, a rail to its chest, `veins` in its rock shell, liquids sealed off)
    and `Village` (huts on a ring around a well, doors to the well, paths, an optional
    `VillageFarm`).
  - Structures keep apart: a site within reach (the two radii) of an earlier structure's
    candidate is dropped. Two structures of one name throw `ArgumentError`.
  - `StructureSite.hashAt` (a cell's hash), `worldY`, `isRock` (the world's stone, strata
    and ores) and `isOpen` (air, its water or lava); `StructureSite.level` takes `floor:`
    (the floor's dy, 0 by default).
  - The generator works out each column's height and biome once a chunk (the surface, the
    plants and the pools share them) where it used to twice.

- `WorldGenSpec.cavern` (a `CavernSpec`, new; null by default): a world that is one great
  cave (VA10) — a slab of its `stone` between a bedrock `floor` and `roof` (7 and 100), opened
  by 3D noise over `threshold` (about two fifths open) and stretched by `scale`, its sea
  (`water`, lava in an underworld) in the open cells up to `seaLevel`, open sky above the
  roof. Each floor above the sea takes its column's biome's `top` over its `under` and its
  plants; `CavernSpec.hangs` (`Plant`s) hang from the ceilings; ores vein the rock;
  structures stand on the lowest floor above the sea, which is what `surfaceHeight` answers
  there. A cavern throws `ArgumentError` for biomes with trees, caves on, or a roof at the
  top of the world.
- `DimensionGenerator` (new): a world of several dimensions, one `WorldGenSpec` each,
  compiled for one seed; the `ChunkGenerator` that hands chunk (x, z) of dimension `d` to
  `specs[d]`'s generator, for the worker isolates. `SpecGenerator.generateIn` still ignores
  its dimension: one spec is one dimension.

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
