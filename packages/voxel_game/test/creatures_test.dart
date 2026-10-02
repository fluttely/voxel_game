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

/// Level grass at y 20 (the first air cell), no caves, no trees.
VoxelGameSpec _flat({
  List<MobSpec> mobs = const [],
  SkySpec sky = SkySpec.alwaysDay,
  Map<String, int> start = const {},
}) => VoxelGameSpec(
  blocks: _blocks,
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  items: const [ItemType('bone', color: 0xEEEEDD)],
  effects: _effects,
  player: PlayerSpec(xp: const XpSpec(), startingItems: start),
  mobs: mobs,
  sky: sky,
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

const _wolf = MobSpec(
  'wolf',
  hp: 12,
  speed: 4.0,
  brain: [Wander()],
  tameWith: ['bone'],
  tamedBrain: [MeleeAttack(damage: 4), PetFight(), Heel()],
);

const _horse = MobSpec(
  'horse',
  hp: 20,
  speed: 5.0,
  halfWidth: 0.5,
  height: 1.6,
  brain: [],
  tameWith: ['bone'],
  tamedBrain: [MountWait()],
  mount: MountSpec(seat: 1.0),
);

int _dropped(VoxelGame game, String item) =>
    game.entities.whereType<ItemPickup>().where((d) => d.stack.id == item).fold(0, (n, d) => n + d.stack.count);

void main() {
  test('a creature the player kills drops its loot and is worth its experience; one the blast kills is not', () async {
    const pig = MobSpec('pig', hp: 6, brain: [], loot: LootTable([LootEntry('dirt', 3, 3, 1.0)]), xp: 7);
    final game = await _start(_flat(mobs: const [pig]));
    final p = game.player;
    final m = game.spawnMob('pig', p.position + Vector3(0, 0, -10));
    m.takeDamage(Damage(100, attacker: p));
    expect(m.isDead, isTrue);
    expect(_dropped(game, 'dirt'), 3, reason: 'its loot table rolled once');
    expect(p.xp, 7);
    final other = game.spawnMob('pig', p.position + Vector3(0, 0, 10));
    other.takeDamage(const Damage(100, source: 'explosion'));
    expect(other.isDead, isTrue);
    expect(p.xp, 7, reason: 'only the player\'s kill is worth experience');
  });

  test('levels grow a creature\'s health, strikes and experience, and a spawn comes at the player\'s', () async {
    const levels = MobLevels(hp: 0.5, damage: 0.25, xp: 1.0, spread: 1, caveBonus: 2);
    expect(levels.levelFor(0, 0, cave: false), 1, reason: 'a player at level 0 meets level 1');
    expect(levels.levelFor(4, 1, cave: true), 8);
    expect(levels.levelFor(0, -1, cave: false), 1, reason: 'never under 1');
    const brute = MobSpec('brute', hp: 10, brain: [], xp: 10, levels: levels, spawn: SpawnRule(maxAlive: 3));
    final game = await _start(_flat(mobs: const [brute]));
    final m = game.spawnMob('brute', game.player.position + Vector3(0, 0, -10));
    expect((m.level, m.hp, m.damageScale, m.xpWorth), (1, 10.0, 1.0, 10));
    m.growTo(3);
    expect((m.level, m.hp, m.maxHp, m.damageScale, m.xpWorth), (3, 20.0, 20.0, 1.5, 30));
    m.removed = true;
    game.player.level = 4;
    game.spawner
      ..enabled = true
      ..minDistance = 6
      ..maxDistance = 14;
    await _run(game, 6.0);
    final spawned = game.mobs.where((m) => !m.removed).toList();
    expect(spawned, isNotEmpty);
    for (final s in spawned) {
      expect(s.level, inInclusiveRange(4, 6), reason: 'the player\'s level plus one, give or take one');
      expect(s.hp, s.maxHp);
    }
  });

  test('a creature that burns by day burns under the open noon sky, not under a roof, not at night', () async {
    const zombie = MobSpec('zombie', hp: 20, brain: [], burnsInDaylight: true);
    final day = await _start(_flat(mobs: const [zombie]));
    final open = day.spawnMob('zombie', day.player.position + Vector3(0, 0, -6));
    final roofed = day.spawnMob('zombie', day.player.position + Vector3(0, 0, 6));
    final over = IVec3.floor(roofed.position) + const IVec3(0, 3, 0);
    for (var x = -2; x <= 2; x++) {
      for (var z = -2; z <= 2; z++) {
        day.world.setBlock(over + IVec3(x, 0, z), day.blocks.indexOf('stone'));
      }
    }
    // The roof's shade is lit in by the next look.
    await _run(day, 1.0);
    final roofedHp = roofed.hp;
    await _run(day, 2.0);
    expect(open.burning, isTrue);
    expect(open.hp, lessThan(20.0));
    expect(roofed.burning, isFalse, reason: 'a roof keeps the full sky off its head');
    expect(roofed.hp, roofedHp);

    final night = await _start(_flat(mobs: const [zombie], sky: const SkySpec(startTime: 0.0, cycle: false)));
    final dark = night.spawnMob('zombie', night.player.position + Vector3(0, 0, -6));
    await _run(night, 2.0);
    expect(dark.hp, 20.0, reason: 'the night burns no one');
  });

  test('a creature that splits dies into its children, at its level, and they are worth their own', () async {
    const slime = MobSpec('slime', hp: 8, brain: [], levels: MobLevels(), splitsInto: MobSplit('small', count: 3));
    const small = MobSpec('small', hp: 2, brain: [], levels: MobLevels());
    final game = await _start(_flat(mobs: const [slime, small]));
    final m = game.spawnMob('slime', game.player.position + Vector3(0, 0, -8))..growTo(3);
    m.takeDamage(Damage(100, attacker: game.player));
    final children = game.mobs.where((c) => c.spec.id == 'small').toList();
    expect(children, hasLength(3));
    expect(children.map((c) => c.level).toSet(), {3});
    await _run(game, 1.0);
    expect(game.mobs.where((c) => c.spec.id == 'slime'), isEmpty);
    expect(game.mobs.where((c) => c.spec.id == 'small'), hasLength(3), reason: 'the children do not split again');
  });

  test('a strike leaves its creature\'s effect on the player', () async {
    const spider = MobSpec(
      'spider',
      hp: 10,
      speed: 3.0,
      brain: [MeleeAttack(damage: 1), Hunt(range: 20)],
      onHit: HitEffect('poison', seconds: 8.0),
    );
    final game = await _start(_flat(mobs: const [spider]));
    game.spawnMob('spider', game.player.position + Vector3(0, 0, -3));
    await _run(game, 3.0);
    expect(game.player.effects.has('poison'), isTrue);
  });

  test('underground, a cave rule spawns in a pocket of air near the player and a surface rule does not', () async {
    const bat = MobSpec('bat', hp: 4, brain: [], spawn: SpawnRule.cave(maxAlive: 4));
    const cow = MobSpec('cow', hp: 4, brain: [], spawn: SpawnRule(maxAlive: 4));
    final game = await _start(_flat(mobs: const [bat, cow]));
    final p = game.player;
    // A room 9 x 9, three high, its floor at y 8, twelve under the grass.
    final c = IVec3.floor(p.position);
    for (var x = -4; x <= 4; x++) {
      for (var z = -4; z <= 4; z++) {
        for (var y = 8; y <= 10; y++) {
          game.world.setBlock(IVec3(c.x + x, y, c.z + z), BlockRegistry.air);
        }
      }
    }
    p.position = Vector3(c.x + 0.5, 8.0, c.z + 0.5);
    p.velocity = Vector3.zero();
    await _run(game, 0.5);
    game.spawner
      ..enabled = true
      ..minDistance = 1
      ..maxDistance = 3
      ..caveShare = 1.0;
    await _run(game, 20.0);
    final bats = game.mobs.where((m) => m.spec.id == 'bat');
    expect(bats, isNotEmpty);
    for (final b in bats) {
      expect(b.position.y, inInclusiveRange(7.9, 10.0), reason: 'in the room, not on the grass');
    }
    expect(game.mobs.where((m) => m.spec.id == 'cow'), isEmpty);
  });

  test('a biome weight multiplies a rule\'s weight there', () {
    const rule = SpawnRule(weight: 4, biomeWeights: {'swamp': 2.5});
    expect(rule.weightIn('swamp'), 10.0);
    expect(rule.weightIn('plains'), 4.0);
  });

  test('a spec\'s creatures are checked: their loot, splits, strikes and experience', () {
    void check(VoxelGameSpec spec) {
      final blocks = spec.buildBlocks();
      spec.checkMobs(spec.buildItems(blocks));
    }

    check(
      _flat(
        mobs: const [
          MobSpec('pig', loot: LootTable([LootEntry('dirt', 1, 1, 1.0)]), xp: 3),
        ],
      ),
    );
    expect(
      () => check(
        _flat(
          mobs: const [
            MobSpec('pig', loot: LootTable([LootEntry('gold', 1, 1, 1.0)])),
          ],
        ),
      ),
      throwsArgumentError,
    );
    expect(() => check(_flat(mobs: const [MobSpec('slime', splitsInto: MobSplit('small'))])), throwsArgumentError);
    expect(() => check(_flat(mobs: const [MobSpec('spider', onHit: HitEffect('fire'))])), throwsArgumentError);
    expect(() => check(_flat(mobs: const [MobSpec('pig'), MobSpec('pig')])), throwsArgumentError);
    expect(
      () => check(_flat(mobs: const [MobSpec('pig', xp: 3)]).copyWith(player: const PlayerSpec())),
      throwsArgumentError,
    );
  });

  test('a use with what tames a creature tames it: it follows its owner, and past thirty metres is carried', () async {
    final game = await _start(_flat(mobs: const [_wolf], start: const {'bone': 3}));
    final p = game.player;
    final wolf = game.spawnMob('wolf', p.position + Vector3(0, 0, -2));
    _face(game, wolf);
    await _run(game, 0.1);
    expect(p.aimedMob, same(wolf));
    expect(p.usableOn(wolf), isTrue);
    expect(game.input.touchTapPrimary, isFalse, reason: 'a finger\'s tap on it uses, as the right button does');
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(wolf.tamed, isTrue);
    expect(wolf.owner, same(p));
    expect(p.inventory.countOf('bone'), 2, reason: 'one bone went');
    expect(p.usableOn(wolf), isFalse, reason: 'a companion is not ridden');
    expect(wolf.running.whereType<Heel>(), isNotEmpty);

    p.position = p.position + Vector3(10, 0, 0);
    await _run(game, 4.0);
    expect(wolf.position.distanceTo(p.position), lessThan(4.5), reason: 'it walked after its owner');
    p.position = p.position + Vector3(0, 0, 34);
    await _run(game, 0.5);
    expect(wolf.position.distanceTo(p.position), lessThan(3.0), reason: 'carried beside its owner');
  });

  test('a taming that does not take still uses up what was offered', () async {
    const shy = MobSpec('shy', hp: 4, brain: [], tameWith: ['bone'], tameChance: 1e-9, tamedBrain: [Heel()]);
    final game = await _start(_flat(mobs: const [shy], start: const {'bone': 1}));
    final m = game.spawnMob('shy', game.player.position + Vector3(0, 0, -2));
    _face(game, m);
    await _run(game, 0.1);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(m.tamed, isFalse);
    expect(game.player.inventory.countOf('bone'), 0);
  });

  test('a companion fights what hunts its owner', () async {
    const zombie = MobSpec('zombie', hp: 30, speed: 1.0, brain: [Hunt(range: 30)]);
    final game = await _start(_flat(mobs: const [_wolf, zombie]));
    final p = game.player;
    final wolf = game.spawnMob('wolf', p.position + Vector3(2, 0, 0))..tame(p);
    final z = game.spawnMob('zombie', p.position + Vector3(0, 0, -10));
    await _run(game, 4.0);
    expect(wolf.target, same(z));
    expect(z.hp, lessThan(30.0), reason: 'the companion bit it');
  });

  test('a tamed mount is ridden by a use, walks by the rider\'s input, and a sneak gets off', () async {
    final game = await _start(_flat(mobs: const [_horse]));
    final p = game.player;
    final horse = game.spawnMob('horse', p.position + Vector3(0, 0, -2.5));
    _face(game, horse);
    await _run(game, 0.1);
    expect(p.usableOn(horse), isFalse, reason: 'a wild mount is not ridden, and the hand holds nothing that tames it');
    horse.tame(p);
    await _run(game, 0.1);
    expect(p.aimedMob, same(horse));
    expect(p.usableOn(horse), isTrue);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.riding, same(horse));
    expect(horse.rider, same(p));
    expect(p.position.distanceTo(horse.seat()), lessThan(1e-6));
    p.yaw = 0.0;
    final from = horse.position.clone();
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 1.0);
    game.input.hold(VoxelAction.moveForward, false);
    expect(from.z - horse.position.z, greaterThan(3.0), reason: 'a second forward at its pace');
    expect(p.position.distanceTo(horse.seat()), lessThan(1e-6), reason: 'the rider sits on it');
    expect(p.aimedMob, isNot(same(horse)), reason: 'the rider does not aim at their own mount');
    game.input.tap(VoxelAction.sneak);
    await _run(game, 0.1);
    expect(p.riding, isNull);
    expect(horse.rider, isNull);
    expect(p.onFloor || p.velocity.y <= 0.0, isTrue);
  });

  test('a mount that dies throws its rider off; tamed creatures neither burn nor wander off the spawner', () async {
    const undead = MobSpec(
      'undead',
      hp: 20,
      brain: [],
      burnsInDaylight: true,
      tameWith: ['bone'],
      tamedBrain: [MountWait()],
      mount: MountSpec(seat: 1.0),
      spawn: SpawnRule(maxAlive: 1),
    );
    final game = await _start(_flat(mobs: const [undead]));
    final p = game.player;
    final m = game.spawnMob('undead', p.position + Vector3(0, 0, -2))..tame(p);
    await _run(game, 2.0);
    expect(m.hp, 20.0, reason: 'a tamed creature does not burn');
    p.ride(m);
    m.takeDamage(const Damage(100));
    await _run(game, 0.1);
    expect(p.riding, isNull);
    final far = game.spawnMob('undead', p.position + Vector3(0, 0, -20))..tame(p);
    game.spawner
      ..enabled = true
      ..despawnDistance = 5;
    await _run(game, 2.0);
    expect(far.removed, isFalse, reason: 'the spawner leaves a tamed creature alone');
  });

  test('a spec\'s tameable creatures are checked', () {
    void check(MobSpec m) {
      final spec = _flat(mobs: [m]);
      spec.checkMobs(spec.buildItems(spec.buildBlocks()));
    }

    check(_wolf);
    expect(() => check(const MobSpec('wolf', tameWith: ['steak'], tamedBrain: [Heel()])), throwsArgumentError);
    expect(() => check(const MobSpec('wolf', tameWith: ['bone'])), throwsArgumentError);
    expect(
      () => check(const MobSpec('wolf', tameWith: ['bone'], tameChance: 0.0, tamedBrain: [Heel()])),
      throwsArgumentError,
    );
  });
}
