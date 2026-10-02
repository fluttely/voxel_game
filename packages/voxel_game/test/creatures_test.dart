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
VoxelGameSpec _flat({List<MobSpec> mobs = const [], SkySpec sky = SkySpec.alwaysDay}) => VoxelGameSpec(
  blocks: _blocks,
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  effects: _effects,
  player: const PlayerSpec(xp: XpSpec()),
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
}
