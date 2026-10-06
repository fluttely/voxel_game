import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5),
  BlockType('dirt', color: 0x74502F, hardness: 0.5),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
  BlockType('bedrock', color: 0x303030, hardness: -1),
  BlockType('wire', color: 0x701010, shape: BlockShape.wire, solid: false, hardness: 0),
  BlockType('wire_lit', color: 0xFF3020, shape: BlockShape.wire, solid: false, hardness: 0, light: 3),
  BlockType('plate', color: 0x909090, shape: BlockShape.slab, opaque: false, hardness: 0.5),
  BlockType('tnt', color: 0xD03020, hardness: 0),
  BlockType.liquid('water', color: 0x3366CC),
];

/// Level grass at y 20, the clock stopped at noon, TNT that bursts 2 m wide
/// two seconds after it is lit, under a plate or by another's blast.
const _spec = VoxelGameSpec(
  blocks: _blocks,
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  sky: SkySpec.alwaysDay,
  mobs: [MobSpec('target', hp: 40, brain: [])],
  signals: SignalSpec(
    wire: ('wire', 'wire_lit'),
    plates: {'plate'},
    explosives: {'tnt': Explosive(radius: 2.0, damage: 10.0, fuse: 2.0, chainFuse: 0.5)},
  ),
);

Future<VoxelGame> _start() async {
  final game = await VoxelGame.startHeadless(_spec);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
  return game;
}

Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

Iterable<LitExplosive> _lit(VoxelGame game) => game.entities.whereType<LitExplosive>().where((e) => !e.removed);

void main() {
  test('lit, an explosive burns its fuse as a body in its place, then bursts', () async {
    final game = await _start();
    final cell = IVec3.floor(game.player.position) + const IVec3(12, 0, 0);
    game.world.setBlockNamed(cell, 'tnt');
    final target = game.spawnMob('target', Vector3(cell.x + 0.5, cell.y.toDouble(), cell.z + 2.5));
    final lit = game.ignite(cell);
    expect(game.world.blockNameAt(cell), 'air', reason: 'the block goes as it is lit');
    expect(lit.block.id, 'tnt');
    expect(lit.fuse, 2.0);
    expect(lit.position, Vector3(cell.x + 0.5, cell.y.toDouble(), cell.z + 0.5));
    expect(lit.white, isFalse);
    await _run(game, 0.5);
    expect(lit.white, isTrue, reason: 'white for a blink every other one');
    expect(lit.left, closeTo(1.5, 0.05));
    await _run(game, 1.4);
    expect(_lit(game), hasLength(1));
    expect(game.world.blockNameAt(cell + IVec3.down), 'grass', reason: 'not yet');
    expect(target.hp, 40.0);
    await _run(game, 0.2);
    expect(_lit(game), isEmpty);
    expect(game.world.blockNameAt(cell + IVec3.down), 'air', reason: 'the ground under it went');
    expect(target.hp, lessThan(40.0), reason: 'the blast reaches 1.5 × its radius');
    game.dispose();
  });

  test('a blast lights the explosives it reaches on a short fuse instead of breaking them', () async {
    final game = await _start();
    final cell = IVec3.floor(game.player.position) + const IVec3(12, 0, 0);
    final near = cell + const IVec3(2, 0, 0), far = cell + const IVec3(8, 0, 0);
    for (final c in [cell, near, far]) {
      game.world.setBlockNamed(c, 'tnt');
    }
    game.ignite(cell);
    await _run(game, 2.05);
    expect(game.world.blockNameAt(near), 'air');
    final chained = _lit(game).single;
    expect(chained.position.x, near.x + 0.5);
    expect(chained.fuse, inInclusiveRange(0.5, 1.5), reason: 'chainFuse to three times it');
    expect(game.world.blockNameAt(far), 'tnt', reason: 'out of reach');
    await _run(game, chained.left + 0.05);
    expect(_lit(game), isEmpty);
    expect(game.world.blockNameAt(near + IVec3.down), 'air', reason: 'it burst in its turn');
    game.dispose();
  });

  test('a lit explosive falls where nothing holds it up', () async {
    final game = await _start();
    final cell = IVec3.floor(game.player.position) + const IVec3(12, 3, 0);
    game.world.setBlockNamed(cell, 'tnt');
    final lit = game.ignite(cell);
    await _run(game, 1.0);
    expect(lit.position.y, closeTo(cell.y - 3.0, 0.01), reason: 'on the ground');
    game.dispose();
  });

  test('a plate stood on lights the explosive under it: a temple\'s trap', () async {
    final game = await _start();
    final feet = IVec3.floor(game.player.position);
    final plate = feet + const IVec3(0, -1, -3);
    game.world.setBlockNamed(plate + IVec3.down, 'tnt');
    game.world.setBlockNamed(plate, 'plate');
    await _run(game, 0.2);
    expect(_lit(game), isEmpty);
    game.player.position = Vector3(plate.x + 0.5, plate.y + 0.6, plate.z + 0.5);
    await _run(game, 0.3);
    expect(game.world.blockNameAt(plate + IVec3.down), 'air');
    expect(_lit(game), hasLength(1));
    game.dispose();
  });

  test('only an explosive is lit, and only by the authority', () async {
    final game = await _start();
    final cell = IVec3.floor(game.player.position) + const IVec3(5, 0, 0);
    game.world.setBlockNamed(cell, 'stone');
    expect(() => game.ignite(cell), throwsArgumentError);
    expect(game.world.blockNameAt(cell), 'stone');
    expect(game.explosives.keys.map((id) => game.blocks[id].id), ['tnt']);
    game.dispose();
  });
}
