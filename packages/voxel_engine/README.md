# voxel_engine

The engine under a voxel game, in pure Dart: a chunk grid, meshing with light
and ambient occlusion, streaming on worker isolates, physics, rays, world
generation, blocks and items, circuits and a network layer. It draws nothing —
a renderer (`voxel_scene`) takes the meshes, and `voxel_game` ties everything
into a playable game.

> **Status: 0.1.0-dev**, the first release. The API can still change.

## The five subjects

Each one is a library of its own. Import only what you use, or
`package:voxel_engine/voxel_engine.dart` for all of it.

| Library | What it does | Depends on |
|:---|:---|:---|
| `core.dart` | chunk grid, mesher, streaming, physics, rays, liquids, pathfinding, the edit save format | — |
| `worldgen.dart` | biomes, terrain, caves, ores, trees, structures, as a declared spec | core |
| `content.dart` | blocks and items by string id, mining, inventory, crafting, loot, effects | core |
| `signals.dart` | wires, levers, lamps, doors, pistons, and rails that lay themselves | core |
| `net.dart` | a TCP host and its clients, exchanging JSON messages | — |

## Install

```yaml
dependencies:
  voxel_engine: ^0.1.0-dev
```

Dart SDK `^3.13.0`. No Flutter dependency: it runs in `dart test`, on a server
and on worker isolates. Not on the web: streaming spawns isolates and `net.dart` is TCP
sockets, through `dart:isolate` and `dart:io`, which a browser does not have.

## Usage

### core — a world you can walk in

1. **Describe your blocks.** Id 0 is air.

   ```dart
   final table = VoxelBlockTable(const [
     VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0), // air
     VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.4, g: 0.4, b: 0.45),  // stone
   ]);
   ```

2. **Write a generator.** It fills one chunk and must be pure in the position.

   ```dart
   class Flat implements ChunkGenerator {
     const Flat();
     @override
     Uint8List generateIn(int cx, int cz, int dimension) {
       final blocks = Uint8List(ChunkSize.volume);
       for (var z = 0; z < ChunkSize.sizeZ; z++) {
         for (var x = 0; x < ChunkSize.sizeX; x++) {
           for (var y = 0; y < 40; y++) {
             blocks[ChunkSize.index(x, y, z)] = 1;
           }
         }
       }
       return blocks;
     }
   }

   ChunkGenerator makeGenerator() => const Flat(); // top-level: sent to each isolate
   ```

3. **Stream chunks around a point.** The sink receives each finished mesh.

   ```dart
   final pool = ChunkWorkerPool(ChunkWorkerConfig(generator: makeGenerator, table: table));
   await pool.start();
   final streamer = ChunkStreamer(table: table, sink: mySink, loadRadius: 4)
     ..jobs = pool
     ..updateAround((x: 0, z: 0));
   // Once a frame:
   streamer.update();
   ```

4. **Read and edit the world.** `streamer.getBlockXYZ`, `streamer.setBlock`,
   `VoxelRaycast.solid(...)` for aiming, `VoxelBody` for anything that walks.

5. **Save only the edits** with `EditDeltaCodec`; the generator rebuilds the rest.

### content — blocks, items and what the player carries

1. **Declare blocks.** Air first; the order numbers them for the engine, and
   `blocks.table` is the `VoxelBlockTable` step 1 above asked for.

   ```dart
   final blocks = BlockRegistry(const [
     BlockType('air', color: 0, solid: false, hardness: -1, drop: ''),
     BlockType('stone', color: 0x7F7F84, hardness: 1.5, tool: 'pickaxe', tier: 1, drop: 'cobblestone'),
     BlockType('cobblestone', color: 0x6E6E70, hardness: 2.0, tool: 'pickaxe'),
   ]);
   ```

2. **Declare items.** Every block you can hold is an item already.

   ```dart
   final items = ItemRegistry([
     ...ItemRegistry.forBlocks(blocks),
     const ItemType('wooden_pickaxe', color: 0xB08850, tool: 'pickaxe', tier: 1, stack: 1, durability: 60),
   ]);
   ```

3. **Mine.** `const MiningRules().mineTime(block, tool)` gives seconds, or -1
   when that tool cannot break it.

4. **Carry things.**

   ```dart
   final bag = Inventory(stackSize: (id) => items[id].stack, maxDurability: (id) => items[id].durability)
     ..add('cobblestone', 10);
   ```

5. **Craft.**

   ```dart
   final book = RecipeBook(const [Recipe('stone', 1, {'cobblestone': 1}, station: 'furnace')]);
   book.craft(book.available('furnace').first, bag);
   ```

### worldgen — a world declared instead of coded

1. **Give it your block ids.** A `BlockRegistry` already has them: `blocks.ids`.

2. **Declare the world.**

   ```dart
   const world = WorldGenSpec(
     biomes: [
       Biome('forest', top: 'grass', under: 'dirt', climate: Climate.wet,
           trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')], treeChance: 90),
       Biome('plains', top: 'grass', under: 'dirt'),
     ],
     beach: Biome('beach', top: 'sand'),
     ores: [Ore('coal_ore', share: 0.11)],
   );
   ```

3. **Compile it with a seed** and use it as the `ChunkGenerator` of step 2 above.

   ```dart
   ChunkGenerator makeGenerator() => world.compile(blocks.ids, 2024);
   ```

4. **Ask it about the world** without generating chunks: `surfaceHeight(x, z)`,
   `biomeAt(x, z)`, `structuresNear(cx, cz)`.

5. **Add a structure** with a build function:

   ```dart
   void tower(StructureSite s) {
     s.level(-2, -2, 2, 2, 'stone', clearTo: 10);
     s.fill(-2, 0, -2, 2, 8, 2, 'stone', hollow: true);
   }
   // structures: [StructureSpec('tower', build: tower, biomes: ['plains'], radius: 3)]
   ```

### signals — circuits and rails

1. **Tell the network about every edit.** It needs a `VoxelEditor`, and your
   world calls `touch` whenever a block changes:

   ```dart
   @override
   bool setBlock(IVec3 cell, int id) {
     final old = getBlockXYZ(cell.x, cell.y, cell.z);
     // ...write the block...
     signals.touch(cell, old, id);
     return true;
   }
   ```

2. **Declare the circuit blocks.**

   ```dart
   final signals = SignalNetwork(world, SignalRules(
     wireOff: wireOff,
     wireOn: wireOn,
     sources: const {leverOn},
     toggles: const {leverOff: leverOn, leverOn: leverOff},
     reactions: {
       lampOff: SignalReactions.swap(lampOff, lampOn),
       lampOn: SignalReactions.swap(lampOff, lampOn),
     },
   ));
   ```

3. **Tick it every frame** with `signals.tick(dt)`, and call `signals.use(cell)`
   when the player clicks a lever.

4. **Rails:** name each rail shape once, then place rails through the graph.

   ```dart
   final rails = RailGraph({railNs: const RailVariant('rail', 'ns'), railEw: const RailVariant('rail', 'ew') /* ... */});
   rails.place(world, cell, railNs); // turns to meet its neighbours
   final next = rails.nextCell(world, cell, RailGraph.e);
   ```

### net — two games in one world

1. **Host.**

   ```dart
   final host = await NetHost.bind(port: 7777);
   host
     ..onJoin = ((peer) => print('player ${peer.id} joined'))
     ..onMessage = ((peer, message) => host.broadcast(message, except: peer.id))
     ..onLeave = ((peer) => print('player ${peer.id} left'));
   ```

2. **Join** from another app or machine.

   ```dart
   final client = await connectToHost('192.168.0.10', port: 7777);
   ```

3. **Talk.** Messages are JSON objects; `t` says what they are.

   ```dart
   client.send({'t': 'pose', 'p': [12.5, 64.0, -3.0]});
   client.listen((message) => print(message['t']));
   ```

4. **Leave.** `await client.close();` runs the host's `onLeave`, and
   `await host.close();` drops everyone.

   On macOS, a Flutter app that hosts or joins needs the
   `com.apple.security.network.server` and `com.apple.security.network.client`
   entitlements.

## Examples

Six files, each runnable on its own:

```sh
dart run example/voxel_engine_example.dart   # the subjects in one run
dart run example/core_example.dart           # streaming, rays, edits, a falling body
dart run example/worldgen_example.dart       # a text map of a four-biome world, then 25 chunks
dart run example/content_example.dart        # blocks, mining, a bag, crafting, loot, effects
dart run example/signals_example.dart        # a lever lights a lamp; a cart rides a rail line
dart run example/net_example.dart            # a host and a client over localhost
```

[`example/voxel_engine_example.dart`](example/voxel_engine_example.dart) is the
one to read first: content declares the blocks, worldgen builds a world out of
the same ids, core meshes a chunk and casts a ray into it, and content mines
what the ray hit into a bag.
