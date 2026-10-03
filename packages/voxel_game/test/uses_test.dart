import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5),
  BlockType('dirt', color: 0x74502F, hardness: 0.5, turnsWith: {'hoe': 'farmland'}),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
  BlockType('farmland', color: 0x5A3A20, hardness: 0.5, drop: 'dirt'),
  BlockType('altar', color: 0xC0A040, hardness: 2.0),
  BlockType('chest', color: 0x8A5A2A, hardness: 2.0, storage: Storage()),
  BlockType('table', color: 0x9A7040, hardness: 2.0),
  BlockType.liquid('water', color: 0x3366CC),
];

const _villager = MobSpec('villager', hp: 20, brain: []);
const _cow = MobSpec('cow', hp: 10, brain: []);
const _wolf = MobSpec('wolf', hp: 10, brain: [], tameWith: ['dirt'], tamedBrain: [Heel()]);

/// Level grass at y 20, no caves, no trees, with [blockUses] and [mobUses].
VoxelGameSpec _flat({Map<String, BlockUse> blockUses = const {}, Map<String, MobUse> mobUses = const {}}) =>
    VoxelGameSpec(
      blocks: _blocks,
      world: const WorldGenSpec(
        terrain: TerrainRecipe.flat(20),
        seaLevel: 5,
        caves: CaveSpec.none,
        biomes: [Biome('plains', top: 'grass', under: 'dirt')],
      ),
      recipes: const [
        Recipe('altar', 1, {'stone': 4}, station: 'table'),
      ],
      player: const PlayerSpec(startingItems: {'stone': 4}),
      mobs: const [_villager, _cow, _wolf],
      sky: SkySpec.alwaysDay,
      blockUses: blockUses,
      mobUses: mobUses,
    );

Future<VoxelGame> _start(VoxelGameSpec spec) async {
  final game = await VoxelGame.startHeadless(spec);
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

void main() {
  test('a use on a block of the game\'s own calls its handler once a press, unless the player sneaks', () async {
    final used = <IVec3>[];
    final game = await _start(_flat(blockUses: {'altar': (game, cell) => used.add(cell)}));
    final p = game.player;
    final altar = IVec3.floor(p.position) + IVec3(0, 0, -2);
    game.world.setBlockNamed(altar, 'altar');
    p.yaw = 0.0;
    p.pitch = -0.45;
    await _run(game, 0.1);
    expect(p.aimedBlock?.block, altar);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(used, [altar]);
    game.input.hold(VoxelAction.use, true);
    await _run(game, 1.0);
    game.input.hold(VoxelAction.use, false);
    expect(used, hasLength(2), reason: 'a hold is one press: the second is the hold\'s own start');
    final stones = p.inventory.countOf('stone');
    expect(stones, 4, reason: 'used, not built against');

    used.clear();
    game.input.hold(VoxelAction.sneak, true);
    await _run(game, 0.1);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    game.input.hold(VoxelAction.sneak, false);
    expect(used, isEmpty);
    expect(p.inventory.countOf('stone'), 3, reason: 'sneaking, the stone in hand is built against it');
    game.dispose();
  });

  test('a use on a creature of the game\'s own calls its handler; a finger\'s tap on it uses', () async {
    final used = <Mob>[];
    final game = await _start(_flat(mobUses: {'villager': (game, mob) => used.add(mob)}));
    final p = game.player;
    final v = game.spawnMob('villager', p.position + Vector3(0, 0, -2));
    final c = game.spawnMob('cow', p.position + Vector3(0, 0, 2));
    final to = v.centre() - p.eyePosition;
    p.yaw = 0.0;
    p.pitch = math.atan2(to.y, 2.0);
    await _run(game, 0.1);
    expect(p.aimedMob, same(v));
    expect(p.usableOn(v), isTrue);
    expect(game.input.touchTapPrimary, isFalse, reason: 'a tap on it uses, not swings');
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(used, [v]);
    expect(v.hp, 20.0);
    expect(p.usableOn(c), isFalse, reason: 'no use declared for a cow');
    v.kill(dropLoot: false);
    expect(p.usableOn(v), isFalse, reason: 'nothing dead is used');
    game.dispose();
  });

  test('the uses are checked when the game is made', () async {
    void check(VoxelGameSpec spec) => spec.checkUses(spec.buildBlocks());
    void nothing(VoxelGame game, IVec3 cell) {}
    void nobody(VoxelGame game, Mob mob) {}

    check(_flat(blockUses: {'altar': nothing}, mobUses: {'villager': nobody}));
    expect(() => check(_flat(blockUses: {'shrine': nothing})), throwsArgumentError, reason: 'no such block');
    expect(() => check(_flat(blockUses: {'chest': nothing})), throwsArgumentError, reason: 'a store');
    expect(() => check(_flat(blockUses: {'dirt': nothing})), throwsArgumentError, reason: 'a hoe tills it');
    expect(() => check(_flat(blockUses: {'table': nothing})), throwsArgumentError, reason: 'a station');
    expect(() => check(_flat(mobUses: {'golem': nobody})), throwsArgumentError, reason: 'no such mob');
    expect(() => check(_flat(mobUses: {'wolf': nobody})), throwsArgumentError, reason: 'a use tames it');
    await expectLater(VoxelGame.startHeadless(_flat(blockUses: {'chest': nothing})), throwsArgumentError);
  });
}
