import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5),
  BlockType('dirt', color: 0x74502F, hardness: 0.5),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
  BlockType('sand', color: 0xDCCB8A, hardness: 0.5, falls: true),
  BlockType('glass', color: 0xCCEEFF, alpha: 0.3, hardness: 0.3),
  BlockType(
    'torch',
    color: 0xFFD070,
    shape: BlockShape.torch,
    solid: false,
    hardness: 0,
    support: Support.below(),
    onWall: 'wall_torch',
  ),
  BlockType(
    'wall_torch',
    color: 0xFFD070,
    shape: BlockShape.wallTorch,
    solid: false,
    hardness: 0,
    drop: 'torch',
    support: Support.side(),
  ),
  BlockType(
    'melon',
    color: 0x5A9A2A,
    hardness: 0.5,
    loot: LootTable([LootEntry('melon_slice', 3, 3, 1.0), LootEntry('seeds', 1, 1, 1.0)]),
  ),
  BlockType.liquid('water', color: 0x3366CC),
];

const _items = [ItemType('melon_slice', color: 0xE04040), ItemType('seeds', color: 0x99BB44)];

/// Level grass at y 20 (its top at 20), no caves, no trees, always day.
const _spec = VoxelGameSpec(
  blocks: _blocks,
  items: _items,
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  sky: SkySpec.alwaysDay,
);

Future<VoxelGame> _start({VoxelGameSpec spec = _spec}) async {
  final game = await VoxelGame.startHeadless(spec);
  game.spawner.enabled = false;
  game.playWithoutCapture = true;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue, reason: 'the spawn chunk loads and the player stands on it');
  return game;
}

/// [seconds] of simulation, letting the chunk jobs land between frames.
Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

/// How many of [item] lie on the ground.
int _dropped(VoxelGame game, String item) =>
    game.entities.whereType<ItemPickup>().where((p) => p.item == item).fold(0, (n, p) => n + p.count);

/// Puts [item] in slot 0 and holds it.
void _hold(PlayerEntity p, String item, [int count = 1]) {
  p.inventory.setSlot(0, ItemStack(item, count));
  p.selectedSlot = 0;
}

/// Stands the player at column ([x], [z]) on the grass, looking along -Z
/// ([pitch] 0 level, negative down).
void _stand(VoxelGame game, int x, int z, {double pitch = 0.0}) {
  game.player
    ..position = Vector3(x + 0.5, 20.0, z + 0.5)
    ..velocity = Vector3.zero()
    ..yaw = 0.0
    ..pitch = pitch;
}

/// A press of use, and the step that reads it.
Future<void> _use(VoxelGame game) async {
  game.input.tap(VoxelAction.use);
  await _run(game, 1 / 60);
}

void main() {
  test('sand falls to where it lands, and a column falls when what holds it goes', () async {
    final game = await _start();
    final w = game.world;
    int at(int y) => w.getBlock(IVec3(8, y, 8));
    w.setBlockNamed(const IVec3(8, 25, 8), 'sand');
    expect(w.blockNameAt(const IVec3(8, 25, 8)), 'air');
    expect(w.blockNameAt(const IVec3(8, 20, 8)), 'sand', reason: 'it lands on the grass');

    w.setBlockNamed(const IVec3(8, 21, 8), 'sand');
    w.setBlockNamed(const IVec3(8, 22, 8), 'sand');
    expect([at(20), at(21), at(22)], everyElement(game.blocks.indexOf('sand')));
    game.breakBlock(const IVec3(8, 19, 8));
    game.breakBlock(const IVec3(8, 18, 8));
    expect(w.blockNameAt(const IVec3(8, 22, 8)), 'air');
    expect([at(18), at(19), at(20)], everyElement(game.blocks.indexOf('sand')), reason: 'the whole column settles');
  });

  test('sand sinks through water to the floor', () async {
    final game = await _start();
    final w = game.world;
    w.setBlockNamed(const IVec3(4, 19, 4), 'water');
    w.setBlockNamed(const IVec3(4, 18, 4), 'water');
    w.setBlockNamed(const IVec3(4, 21, 4), 'sand');
    expect(w.blockNameAt(const IVec3(4, 18, 4)), 'sand');
  });

  test('a torch drops when its floor goes, a wall torch when its wall goes', () async {
    final game = await _start();
    final w = game.world;
    w.setBlockNamed(const IVec3(8, 20, 8), 'torch');
    game.breakBlock(const IVec3(8, 19, 8));
    expect(w.blockNameAt(const IVec3(8, 20, 8)), 'air');
    expect(_dropped(game, 'torch'), 1);

    w.setBlockNamed(const IVec3(10, 21, 8), 'stone');
    w.setBlockNamed(const IVec3(10, 21, 9), 'wall_torch');
    game.breakBlock(const IVec3(10, 21, 8));
    expect(w.blockNameAt(const IVec3(10, 21, 9)), 'air');
    expect(_dropped(game, 'torch'), 2, reason: 'a wall torch drops a torch');
  });

  test('a torch placed against a wall is a wall torch, and nothing is placed where it would not stand', () async {
    final game = await _start();
    final w = game.world, p = game.player;
    _stand(game, 0, 0);
    _hold(p, 'torch', 4);
    w.setBlockNamed(const IVec3(0, 21, -2), 'stone');
    await _use(game);
    expect(w.blockNameAt(const IVec3(0, 21, -1)), 'wall_torch', reason: 'the stone is ahead at eye height');
    expect(p.inventory.countOf('torch'), 3);

    // A glass wall is not opaque: a wall torch does not lean on it.
    w.setBlockNamed(const IVec3(0, 21, -1), 'air');
    w.setBlockNamed(const IVec3(0, 21, -2), 'glass');
    await _run(game, 0.3);
    await _use(game);
    expect(w.blockNameAt(const IVec3(0, 21, -1)), 'air');
    expect(p.inventory.countOf('torch'), 3);

    // Looking down, the torch stands on the grass.
    _stand(game, 0, 0, pitch: -1.5);
    await _run(game, 0.3);
    await _use(game);
    expect(w.blockNameAt(const IVec3(0, 20, 0)), 'torch');
  });

  test('a block with loot drops what the table rolls, not itself', () async {
    final game = await _start();
    game.world.setBlockNamed(const IVec3(8, 20, 8), 'melon');
    game.breakBlock(const IVec3(8, 20, 8));
    expect(_dropped(game, 'melon_slice'), 3);
    expect(_dropped(game, 'seeds'), 1);
    expect(_dropped(game, 'melon'), 0);
  });

  test('a block whose loot names an unknown item is refused', () {
    const bad = VoxelGameSpec(
      blocks: [
        BlockType('melon', color: 0, loot: LootTable([LootEntry('slice', 1, 1, 1.0)])),
      ],
      world: WorldGenSpec(biomes: [Biome('plains', top: 'melon')]),
    );
    expect(() => bad.buildItems(bad.buildBlocks()), throwsArgumentError);
  });
}
