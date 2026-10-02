import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5),
  BlockType('dirt', color: 0x74502F, hardness: 0.5),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
  BlockType.liquid('water', color: 0x3366CC),
];

const _effects = [EffectType('poison', 'Poison', 0.3, 0.6, 0.2, period: 1.0, damage: 1.0, bad: true)];

const _cow = MobSpec('cow', hp: 20, brain: []);
const _ghost = MobSpec('ghost', hp: 10, brain: [], gait: Gait.fly, ghost: true);

/// Level grass at y 20 (the first air cell), no caves, no trees, always day.
VoxelGameSpec _flat({List<MobSpec> mobs = const [_cow, _ghost], PlayerSpec player = const PlayerSpec()}) =>
    VoxelGameSpec(
      blocks: _blocks,
      world: const WorldGenSpec(
        terrain: TerrainRecipe.flat(20),
        seaLevel: 5,
        caves: CaveSpec.none,
        biomes: [Biome('plains', top: 'grass', under: 'dirt')],
      ),
      effects: _effects,
      player: player,
      mobs: mobs,
      sky: SkySpec.alwaysDay,
    );

Future<VoxelGame> _start(VoxelGameSpec spec) async {
  final game = await VoxelGame.startHeadless(spec);
  game.spawner.enabled = false;
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

/// Turns the player to look at [m]'s middle.
void _face(VoxelGame game, Mob m) {
  final p = game.player;
  final to = m.centre() - p.eyePosition;
  p.yaw = -Vector3(0, 0, -1).angleToSigned(Vector3(to.x, 0, to.z).normalized(), Vector3(0, 1, 0));
  p.pitch = math.atan2(to.y, Vector3(to.x, 0, to.z).length);
}

void main() {
  test("a critical swing: the player's chance, the multiplier rounded, its number marked", () async {
    final game = await _start(_flat(player: const PlayerSpec(critChance: 1.0)));
    final cow = game.spawnMob('cow', game.player.position + Vector3(0, 0, -2));
    _face(game, cow);
    await _run(game, 0.1);
    game.input.tap(VoxelAction.attack);
    await _run(game, 0.1);
    expect(cow.hp, 18.0, reason: 'a bare hand (1) times 1.5 is 1.5, rounded to 2');
    final number = game.damageNumbers.shown.last;
    expect((number.amount, number.crit), (2.0, true));
    expect(game.player.critical(3.0), (amount: 5.0, crit: true));

    final plain = await _start(_flat());
    final other = plain.spawnMob('cow', plain.player.position + Vector3(0, 0, -2));
    _face(plain, other);
    await _run(plain, 0.1);
    plain.input.tap(VoxelAction.attack);
    await _run(plain, 0.1);
    expect(other.hp, 19.0, reason: 'no chance declared, no roll');
    expect(plain.damageNumbers.shown.last.crit, isFalse);
    expect(() => PlayerSpec(critChance: 1.5), throwsA(isA<AssertionError>()));
  });

  test('a blow is felt: the pose holds, then the white passes; a burn only shakes', () async {
    final game = await _start(_flat());
    final cow = game.spawnMob('cow', game.player.position + Vector3(0, 0, -4));
    await _run(game, 0.5);
    cow.takeDamage(Damage(2.0, from: game.player.position, knockback: 6.0, attacker: game.player));
    expect(cow.frozen, isTrue);
    expect(cow.flashing, isTrue);
    expect(cow.motor.stagger, greaterThan(0.0), reason: 'the shove carries it, its own walk does not steer');
    await _run(game, 0.07);
    expect(cow.frozen, isFalse, reason: 'the hit-stop is ${Mob.hitStop} s');
    expect(cow.flashing, isTrue, reason: 'the white lasts ${Mob.hitFlash} s');
    await _run(game, 0.05);
    expect(cow.flashing, isFalse);

    cow.takeDamage(const Damage(0.5, source: 'burning', internal: true));
    expect(cow.frozen || cow.flashing, isFalse, reason: 'a hurt from within is no blow');
  });

  test('a creature that dies stays whole while it topples, then fades out', () {
    expect(Mob.opacityAfterDeath(0.0), 1.0);
    expect(Mob.opacityAfterDeath(Mob.toppleSeconds), 1.0);
    final half = Mob.opacityAfterDeath(Mob.toppleSeconds + Mob.fadeSeconds / 2);
    expect(half, 0.5);
    expect(Mob.opacityAfterDeath(Mob.toppleSeconds + Mob.fadeSeconds), 0.0);
    // By steps, so every dying creature at one step shares one material.
    for (var t = 0.0; t < 1.0; t += 0.013) {
      expect(
        Mob.opacityAfterDeath(t) * Mob.fadeSteps,
        closeTo((Mob.opacityAfterDeath(t) * Mob.fadeSteps).round(), 1e-9),
      );
    }
  });

  test('a ghost is drawn see-through, a creature on fire orange, and fire burns until it is out', () async {
    final game = await _start(_flat());
    final p = game.player;
    final ghost = game.spawnMob('ghost', p.position + Vector3(0, 2, -6));
    final cow = game.spawnMob('cow', p.position + Vector3(4, 0, -4));
    await _run(game, 0.5);
    expect(ghost.tint, Vector4(0.85, 0.92, 1.0, Mob.ghostAlpha));
    expect(cow.tint, Vector4(1, 1, 1, 1));
    expect(cow.burning, isFalse, reason: 'a cow does not burn by day');

    final embers = game.debris.system.storage.aliveCount;
    cow.ignite(2.0);
    expect(cow.burning, isTrue, reason: 'alight at once');
    expect(cow.tint, Vector4(1.0, 0.55, 0.15, 1.0));
    await _run(game, 3.0);
    expect(cow.burning, isFalse, reason: 'out after its 2 s');
    expect(cow.hp, inInclusiveRange(17.5, 18.5), reason: '${Mob.burnDamage} every ${Mob.burnEvery} s for 2 s');
    expect(game.debris.system.storage.aliveCount, greaterThan(embers), reason: 'each burning look sheds an ember');

    // Water puts it out, and nothing in it catches fire.
    final water = game.blocks.indexOf('water');
    final feet = IVec3.floor(cow.position);
    game.world.setBlock(feet, water);
    game.world.setBlock(feet + IVec3.up, water);
    await _run(game, 0.2);
    final wet = cow.hp;
    cow.ignite(4.0);
    await _run(game, 1.5);
    expect(cow.burning, isFalse);
    expect(cow.hp, wet);
    expect(() => cow.ignite(0.0), throwsArgumentError);
  });

  test("a fire shot sets the creature it hits burning; a shot's effect stays on the player it hurts", () async {
    final game = await _start(_flat(player: const PlayerSpec(critChance: 1.0)));
    final p = game.player;
    final cow = game.spawnMob('cow', p.position + Vector3(0, 0, -6));
    await _run(game, 0.2);
    game.shoot(ProjectileSpec.fireball, from: p.eyePosition, at: cow.centre(), owner: p);
    await _run(game, 0.6);
    expect(cow.burning, isTrue);
    expect(game.damageNumbers.shown.first.crit, isTrue, reason: "the player's shot rolls the player's chance");
    expect(game.damageNumbers.shown.first.amount, 6.0, reason: '4 times 1.5');

    const dart = ProjectileSpec(kind: 'dart', gravity: 0.0, onHit: HitEffect('poison', seconds: 3.0));
    game.shoot(dart, from: cow.eye(), at: p.centre(), owner: cow);
    await _run(game, 0.6);
    expect(p.effects.rows.keys, contains('poison'));
    expect(p.hp, lessThan(p.maxHp));
  });

  test('a ranged creature whose shot leaves an effect not declared is refused', () async {
    const witch = MobSpec(
      'witch',
      brain: [RangedAttack(projectile: ProjectileSpec(onHit: HitEffect('slowness')))],
    );
    await expectLater(VoxelGame.startHeadless(_flat(mobs: const [witch])), throwsArgumentError);
  });

  test('a blow shakes the camera by its damage and is felt; a hurt from within is not', () async {
    final game = await _start(_flat());
    final p = game.player;
    p.takeDamage(Damage(2.0, from: p.position + Vector3(1, 0, 0), knockback: 4.0));
    expect(p.shake, closeTo(0.2, 1e-9), reason: 'the damage over 10');
    expect(p.frozen && p.flashing, isTrue);
    await _run(game, 0.2);
    expect(p.shake, 0.0, reason: 'gone in ${PlayerEntity.shakeSeconds} s');
    expect(p.flashing, isFalse);

    await _run(game, 0.5);
    p.takeDamage(const Damage(9.0, source: 'fall'));
    expect(p.shake, closeTo(0.3, 1e-9), reason: 'never more than 0.3 m');
    await _run(game, 0.5);
    p.takeDamage(const Damage(1.0, source: 'poison', internal: true));
    expect(p.shake, 0.0);
    expect(p.flashing, isFalse);
  });

  test('mining chips the block, and breaking it bursts it', () async {
    final game = await _start(_flat());
    final p = game.player;
    final chips = game.debris.system.storage;
    expect(chips.aliveCount, 0);
    p.pitch = -1.5; // straight down
    game.input.hold(VoxelAction.attack, true);
    for (var i = 0; i < 300 && game.world.getBlock(IVec3.floor(p.position) + IVec3.down) != 0; i++) {
      await _run(game, 1 / 60);
    }
    game.input.hold(VoxelAction.attack, false);
    expect(chips.aliveCount, greaterThanOrEqualTo(12 + 2), reason: 'two a dig, a dozen at the break');
    final grass = game.blocks[game.blocks.indexOf('grass')];
    final last = chips.aliveCount - 1;
    expect(chips.colorG[last] / chips.colorR[last], closeTo(grass.g / grass.r, 0.1), reason: "the block's colour");
  });
}
