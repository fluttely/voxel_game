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
  // A door: two high, across the way the player looks, opened and closed by use.
  BlockType(
    'door_z',
    color: 0x9A7040,
    shape: BlockShape.panelZ,
    opaque: false,
    drop: 'door',
    tall: true,
    support: Support.below(),
    facing: Facing.axis(x: 'door_x', z: 'door_z'),
    usedInto: 'door_z_open',
  ),
  BlockType(
    'door_x',
    color: 0x9A7040,
    shape: BlockShape.panelX,
    opaque: false,
    drop: 'door',
    tall: true,
    support: Support.below(),
    facing: Facing.axis(x: 'door_x', z: 'door_z'),
    usedInto: 'door_x_open',
  ),
  BlockType(
    'door_z_open',
    color: 0x9A7040,
    shape: BlockShape.panelX,
    solid: false,
    drop: 'door',
    tall: true,
    support: Support.below(),
    usedInto: 'door_z',
  ),
  BlockType(
    'door_x_open',
    color: 0x9A7040,
    shape: BlockShape.panelZ,
    solid: false,
    drop: 'door',
    tall: true,
    support: Support.below(),
    usedInto: 'door_x',
  ),
  BlockType(
    'stairs_n',
    color: 0xB08850,
    shape: BlockShape.stairsN,
    facing: Facing.compass(north: 'stairs_n', east: 'stairs_e', south: 'stairs_s', west: 'stairs_w'),
  ),
  BlockType('stairs_e', color: 0xB08850, shape: BlockShape.stairsE, drop: 'stairs_n'),
  BlockType('stairs_s', color: 0xB08850, shape: BlockShape.stairsS, drop: 'stairs_n'),
  BlockType('stairs_w', color: 0xB08850, shape: BlockShape.stairsW, drop: 'stairs_n'),
  // An iron door: tall, turned by a signal only.
  BlockType('iron_door', color: 0xCCCCCC, shape: BlockShape.panelZ, opaque: false, tall: true),
  BlockType('iron_door_open', color: 0xCCCCCC, shape: BlockShape.panelX, solid: false, tall: true),
  BlockType('wire', color: 0x600000, shape: BlockShape.wire, solid: false),
  BlockType('wire_lit', color: 0xFF0000, shape: BlockShape.wire, solid: false),
];

const _items = [
  ItemType('melon_slice', color: 0xE04040),
  ItemType('seeds', color: 0x99BB44),
  ItemType('door', color: 0x9A7040, block: 'door_z', stack: 16),
  ItemType('bucket', color: 0xA0A0A8, stack: 16, bucket: Bucket.empty({'water': 'water_bucket'})),
  ItemType('water_bucket', color: 0x3366CC, stack: 1, bucket: Bucket.full('water', empties: 'bucket')),
];

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

/// A press of use, and the steps that read it: a frame of one step's length
/// does not always run one.
Future<void> _use(VoxelGame game) async {
  game.input.tap(VoxelAction.use);
  await _run(game, 0.05);
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

  test('a door goes up two high, across the way the player looks, and a use turns both halves', () async {
    final game = await _start();
    final w = game.world, p = game.player;
    _hold(p, 'door', 2);
    // Aimed at the top of the grass two cells ahead.
    _stand(game, 0, 0, pitch: -0.68);
    await _use(game);
    expect(w.blockNameAt(const IVec3(0, 20, -2)), 'door_z', reason: 'looking along z, the panel spans x');
    expect(w.blockNameAt(const IVec3(0, 21, -2)), 'door_z');
    expect(p.inventory.countOf('door'), 1);

    // Looking level, the upper half is under the crosshair: a press opens both.
    _stand(game, 0, 0);
    await _run(game, 0.3);
    await _use(game);
    expect(w.blockNameAt(const IVec3(0, 20, -2)), 'door_z_open');
    expect(w.blockNameAt(const IVec3(0, 21, -2)), 'door_z_open');
    // Holding use turns it once, as it goes down: no flapping, no building
    // against it.
    game.input.hold(VoxelAction.use, true);
    await _run(game, 0.6);
    game.input.hold(VoxelAction.use, false);
    expect(w.blockNameAt(const IVec3(0, 20, -2)), 'door_z');
    expect(w.blockNameAt(const IVec3(0, 21, -2)), 'door_z');
    expect(w.blockNameAt(const IVec3(0, 21, -1)), 'air');
    expect(p.inventory.countOf('door'), 1);

    // Looking along x, the panel spans z.
    game.player
      ..position = Vector3(4.5, 20.0, 0.5)
      ..yaw = -1.5707963
      ..pitch = -0.68;
    _hold(p, 'door', 1);
    await _run(game, 0.3);
    await _use(game);
    expect(w.blockNameAt(const IVec3(6, 20, 0)), 'door_x');
    expect(w.blockNameAt(const IVec3(6, 21, 0)), 'door_x');
  });

  test('a door does not close on a body standing in it', () async {
    final game = await _start();
    final w = game.world;
    w.setBlockNamed(const IVec3(0, 20, 0), 'door_z_open');
    w.setBlockNamed(const IVec3(0, 21, 0), 'door_z_open');
    _stand(game, 0, 0);
    expect(game.blockRules.use(const IVec3(0, 21, 0)), isTrue, reason: 'the use is spent on the door');
    expect(w.blockNameAt(const IVec3(0, 20, 0)), 'door_z_open');
    _stand(game, 3, 3);
    expect(game.blockRules.use(const IVec3(0, 21, 0)), isTrue);
    expect(w.blockNameAt(const IVec3(0, 20, 0)), 'door_z');
    expect(w.blockNameAt(const IVec3(0, 21, 0)), 'door_z');
  });

  test('breaking one half of a door takes the other, and stacked doors pair from the bottom', () async {
    final game = await _start();
    final w = game.world;
    for (var y = 20; y < 24; y++) {
      w.setBlockNamed(IVec3(8, y, 8), 'door_z');
    }
    game.breakBlock(const IVec3(8, 22, 8));
    expect(w.blockNameAt(const IVec3(8, 23, 8)), 'air', reason: 'the upper door went whole');
    expect(w.blockNameAt(const IVec3(8, 21, 8)), 'door_z', reason: 'the lower door stays');
    expect(_dropped(game, 'door'), 1, reason: 'one door, not one per half');

    game.breakBlock(const IVec3(8, 21, 8));
    expect(w.blockNameAt(const IVec3(8, 20, 8)), 'air');
    expect(_dropped(game, 'door'), 2);
  });

  test('a door turned by a signal keeps both halves', () async {
    final game = await _start(
      spec: _spec.copyWith(
        signals: () => const SignalSpec(wire: ('wire', 'wire_lit'), doors: {'iron_door': 'iron_door_open'}),
      ),
    );
    final w = game.world;
    w.setBlockNamed(const IVec3(8, 20, 8), 'iron_door');
    w.setBlockNamed(const IVec3(8, 21, 8), 'iron_door');
    w.setBlockNamed(const IVec3(8, 20, 8), 'iron_door_open');
    w.setBlockNamed(const IVec3(8, 21, 8), 'iron_door_open');
    expect(w.blockNameAt(const IVec3(8, 20, 8)), 'iron_door_open');
    expect(w.blockNameAt(const IVec3(8, 21, 8)), 'iron_door_open');
    expect(game.blockRules.use(const IVec3(8, 20, 8)), isFalse, reason: 'an iron door has no use');
  });

  test('stairs climb away from the player who places them', () async {
    final game = await _start();
    final w = game.world, p = game.player;
    _hold(p, 'stairs_n', 2);
    _stand(game, 0, 0, pitch: -0.68);
    await _use(game);
    expect(w.blockNameAt(const IVec3(0, 20, -2)), 'stairs_n');
    game.player
      ..position = Vector3(4.5, 20.0, 0.5)
      ..yaw = -1.5707963;
    await _run(game, 0.3);
    await _use(game);
    expect(w.blockNameAt(const IVec3(6, 20, 0)), 'stairs_e');
  });

  test('an empty bucket scoops a source, and a full one pours it', () async {
    final game = await _start();
    final w = game.world, p = game.player;
    const pool = IVec3(0, 20, -2);
    w.setBlockNamed(pool, 'water');
    _hold(p, 'bucket', 3);
    _stand(game, 0, 0, pitch: -0.51);
    await _use(game);
    expect(w.blockNameAt(pool), 'air');
    expect(p.inventory.countAt(0), 2, reason: 'one bucket of the stack was filled');
    expect(p.inventory.countOf('water_bucket'), 1, reason: 'the full one went to the bag');

    await _run(game, 0.3);
    await _use(game);
    expect(p.inventory.countOf('bucket'), 2, reason: 'nothing left to scoop');

    _hold(p, 'water_bucket');
    _stand(game, 0, 0, pitch: -0.68);
    await _run(game, 0.3);
    await _use(game);
    expect(w.blockNameAt(pool), 'water', reason: 'poured against the top of the grass');
    expect(p.inventory.idAt(0), 'bucket', reason: 'the last full bucket empties in the hand');
  });

  test('a bucket of a liquid there is not is refused', () {
    final bad = _spec.copyWith(
      items: [
        ..._items,
        const ItemType('lava_bucket', color: 0xFF6010, bucket: Bucket.full('lava', empties: 'bucket')),
      ],
    );
    expect(() => bad.buildItems(bad.buildBlocks()), throwsArgumentError);
  });
}
