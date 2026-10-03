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

const _target = MobSpec('target', hp: 40, brain: []);
const _hunter = MobSpec('hunter', hp: 40, speed: 3.0, brain: [Hunt(range: 40)]);
const _wolf = MobSpec('wolf', hp: 40, speed: 3.0, brain: [Hunt(whenProvoked: true), Wander()]);

/// Level grass at y 20, no caves, no trees, a player with no armour.
VoxelGameSpec _flat({PlayerSpec player = const PlayerSpec()}) => VoxelGameSpec(
  blocks: _blocks,
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  player: player,
  mobs: const [_target, _hunter, _wolf],
  sky: SkySpec.alwaysDay,
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

/// Turns the player to look at [m]'s middle.
void _face(VoxelGame game, Mob m) {
  final p = game.player;
  final to = m.centre() - p.eyePosition;
  p.yaw = -Vector3(0, 0, -1).angleToSigned(Vector3(to.x, 0, to.z).normalized(), Vector3(0, 1, 0));
  p.pitch = math.atan2(to.y, Vector3(to.x, 0, to.z).length);
}

/// One swing at [m], bare-handed.
Future<void> _swingAt(VoxelGame game, Mob m) async {
  _face(game, m);
  await _run(game, 0.1);
  expect(game.player.aimedMob, same(m));
  game.input.hold(VoxelAction.attack, true);
  await _run(game, 1 / 60);
  game.input.hold(VoxelAction.attack, false);
  await _run(game, 0.5);
}

/// How far the player walks forward in [seconds].
Future<double> _walk(VoxelGame game, double seconds, {bool sprint = false}) async {
  final p = game.player;
  final from = p.position.clone();
  game.input.hold(VoxelAction.moveForward, true);
  game.input.hold(VoxelAction.sprint, sprint);
  await _run(game, seconds);
  game.input.hold(VoxelAction.moveForward, false);
  game.input.hold(VoxelAction.sprint, false);
  final d = Vector3(p.position.x - from.x, 0, p.position.z - from.z).length;
  await _run(game, 0.3);
  return d;
}

void main() {
  test('a boost raises the most health and outlasts a death; taken back, the health comes down to it', () async {
    final game = await _start(_flat());
    final p = game.player;
    p.boosts['blessing'] = const Boost(maxHp: 6);
    expect(p.maxHp, 26.0);
    p.hp = 26.0;
    await _run(game, 0.1);
    expect(p.hp, 26.0, reason: 'a boost\'s health is the player\'s to fill');
    p.kill();
    await _run(game, 1.1);
    game.respawn();
    expect(p.boosts.keys, ['blessing'], reason: 'a respawn keeps the game\'s boosts, unlike the effects');
    expect(p.hp, 26.0);
    p.boosts.remove('blessing');
    await _run(game, 1 / 60);
    expect(p.hp, 20.0);
    game.dispose();
  });

  test('boosts multiply speed, damage and mining with each other and the effects, and add armour', () async {
    final game = await _start(_flat());
    final p = game.player;
    final plain = await _walk(game, 1.0);
    p.boosts['quick'] = const Boost(speed: 1.5, damage: 2.0, mining: 3.0, armor: 4.0);
    p.boosts['quicker'] = const Boost(speed: 4 / 3);
    expect(p.speedMultiplier, closeTo(2.0, 1e-9));
    expect(p.damageMultiplier, 2.0);
    expect(p.miningMultiplier, 3.0);
    expect(p.armor, 4.0);
    final boosted = await _walk(game, 1.0);
    expect(boosted / plain, closeTo(2.0, 0.25), reason: 'twice the pace');

    final m = game.spawnMob('target', p.position + Vector3(0, 0, -2));
    await _swingAt(game, m);
    expect(m.hp, 38.0, reason: 'the hand\'s 1 doubled');
    game.dispose();
  });

  test('the filters on a hurt run in order before armour; one that brings it to nothing is not felt', () async {
    final game = await _start(_flat());
    final p = game.player;
    p.damageIn['halved'] = (damage, amount) => amount / 2;
    p.damageIn['less one'] = (damage, amount) => math.max(amount - 1, 0);
    expect(p.takeDamage(const Damage(10)), 4.0);
    expect(p.hp, 16.0);
    expect(p.graceLeft, 0.4, reason: 'PlayerSpec.grace after a blow');
    await _run(game, 0.6);
    p.boosts['plate'] = const Boost(armor: 5);
    expect(p.takeDamage(const Damage(10)), 2.0, reason: 'the filtered 4, less 5 points of armour at 0.4');
    p.boosts.clear();
    await _run(game, 0.6);

    p.damageIn
      ..clear()
      ..['dodge'] = (damage, amount) => damage.internal ? amount : 0.0;
    final before = p.hp;
    expect(p.takeDamage(const Damage(5)), 0.0);
    expect(p.hp, before);
    expect(p.hurtFlash, 0.0, reason: 'a dodged blow is not felt');
    expect(p.graceLeft, 0.0, reason: 'and leaves no grace');
    expect(p.takeDamage(const Damage(1, internal: true)), 1.0);

    p.damageIn['broken'] = (damage, amount) => -1.0;
    expect(() => p.takeDamage(const Damage(1, internal: true)), throwsStateError);
    game.dispose();
  });

  test('a blow the player deals goes through the game\'s filters', () async {
    final game = await _start(_flat());
    final p = game.player;
    final m = game.spawnMob('target', p.position + Vector3(0, 0, -2));
    p.damageOut['slayer'] = (target, amount) => target.spec.id == 'target' ? amount * 3 : amount;
    await _swingAt(game, m);
    expect(m.hp, 37.0);
    game.dispose();
  });

  test('a sprint veto stops the sprint, on foot and in what sprinting says', () async {
    final game = await _start(_flat());
    final p = game.player;
    game.input.hold(VoxelAction.moveForward, true);
    game.input.hold(VoxelAction.sprint, true);
    await _run(game, 0.5);
    expect(p.sprinting, isTrue);
    var tired = true;
    p.sprintVetoes['stamina'] = () => tired;
    await _run(game, 0.5);
    expect(p.sprinting, isFalse);
    final flat = math.sqrt(p.velocity.x * p.velocity.x + p.velocity.z * p.velocity.z);
    expect(flat, closeTo(p.spec.walkSpeed, 0.3), reason: 'walking, the button still held');
    tired = false;
    await _run(game, 0.1);
    expect(p.sprinting, isTrue);
    game.input.hold(VoxelAction.moveForward, false);
    await _run(game, 1 / 60);
    expect(p.sprinting, isFalse, reason: 'no sprint standing still');
    game.dispose();
  });

  test('a grace given from code stops blows from outside, not hurts from within', () async {
    final game = await _start(_flat());
    final p = game.player;
    p.grantGrace(2.0);
    expect(p.takeDamage(const Damage(3)), 0.0);
    expect(p.takeDamage(const Damage(1, internal: true)), 1.0);
    p.grantGrace(0.5);
    expect(p.graceLeft, 2.0, reason: 'the longer grace is kept');
    await _run(game, 2.1);
    expect(p.takeDamage(const Damage(3)), 3.0);
    expect(() => p.grantGrace(0), throwsArgumentError);
    game.dispose();

    final graceless = await _start(_flat(player: const PlayerSpec(grace: 0)));
    expect(graceless.player.takeDamage(const Damage(2)), 2.0);
    expect(graceless.player.takeDamage(const Damage(2)), 2.0, reason: 'no grace declared, the second blow lands');
    graceless.dispose();
  });

  test('a stunned creature neither thinks nor walks until the stun is over', () async {
    final game = await _start(_flat());
    final p = game.player;
    final h = game.spawnMob('hunter', p.position + Vector3(0, 0, -12));
    await _run(game, 0.1);
    h.stun(1.2);
    expect(h.stunned, isTrue);
    await _run(game, 0.4);
    final at = h.position.clone();
    await _run(game, 0.6);
    expect(
      Vector3(h.position.x - at.x, 0, h.position.z - at.z).length,
      lessThan(0.05),
      reason: 'stopped, once its stride died',
    );
    await _run(game, 1.5);
    expect(h.stunned, isFalse);
    expect(h.position.distanceTo(p.position), lessThan(at.distanceTo(p.position) - 2.0), reason: 'it hunts again');
    expect(() => h.stun(0), throwsArgumentError);
    game.dispose();
  });

  test('a slowed creature walks at its share of its pace; a second slow keeps the slower and the longer', () async {
    final game = await _start(_flat());
    final p = game.player;
    final a = game.spawnMob('hunter', p.position + Vector3(0, 0, -14));
    final b = game.spawnMob('hunter', p.position + Vector3(0, 0, 14));
    b.slow(0.5, 10.0);
    b.slow(0.8, 1.0);
    expect(b.pace, 0.5);
    final aFrom = a.position.distanceTo(p.position), bFrom = b.position.distanceTo(p.position);
    await _run(game, 1.5);
    final aWent = aFrom - a.position.distanceTo(p.position), bWent = bFrom - b.position.distanceTo(p.position);
    expect(bWent / aWent, closeTo(0.5, 0.15));
    expect(() => b.slow(1.0, 1.0), throwsArgumentError);
    game.dispose();
  });

  test('a creature made to forget drops its quarrel', () async {
    final game = await _start(_flat());
    final p = game.player;
    final w = game.spawnMob('wolf', p.position + Vector3(0, 0, -6));
    w.takeDamage(Damage(1, attacker: p, from: p.position));
    await _run(game, 0.2);
    expect(w.target, same(p));
    w.forget();
    expect(w.target, isNull);
    expect(w.lastHurtBy, isNull);
    await _run(game, 0.5);
    expect(w.target, isNull, reason: 'it hunts only who hurt it, and forgot who');
    game.dispose();
  });
}
