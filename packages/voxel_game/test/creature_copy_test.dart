import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

/// A creature with every field set off its default, so a copy that drops one
/// shows it.
const MobSpec _full = MobSpec(
  'sheep_lord',
  name: 'Lord of Sheep',
  hp: 40,
  speed: 3.0,
  halfWidth: 0.5,
  height: 2.0,
  rig: Rig.humanoid(skin: 0x123456),
  gait: Gait.hop,
  brain: [MeleeAttack(damage: 4), Wander()],
  loot: LootTable([LootEntry('wool', 1, 2, 1.0)]),
  xp: 9,
  levels: MobLevels(hp: 0.3),
  burnsInDaylight: true,
  splitsInto: MobSplit('sheep', count: 3),
  onHit: HitEffect('poison', seconds: 2.0),
  tameWith: ['wheat'],
  tameChance: 0.25,
  tamedBrain: [Heel()],
  mount: MountSpec(seat: 1.1),
  yields: {'bucket': 'milk_bucket'},
  fleece: Fleece('wool'),
  persistent: true,
  ghost: true,
  invulnerable: true,
  spawn: SpawnRule(biomes: ['plains'], group: (2, 3)),
  knockbackResistance: 0.5,
  hurtSound: 'baa',
  boss: true,
);

List<Object?> _fields(MobSpec s) => [
  s.id,
  s.name,
  s.hp,
  s.speed,
  s.halfWidth,
  s.height,
  s.rig,
  s.gait,
  s.brain,
  s.loot,
  s.xp,
  s.levels,
  s.burnsInDaylight,
  s.splitsInto,
  s.onHit,
  s.tameWith,
  s.tameChance,
  s.tamedBrain,
  s.mount,
  s.yields,
  s.fleece,
  s.persistent,
  s.ghost,
  s.invulnerable,
  s.spawn,
  s.knockbackResistance,
  s.hurtSound,
  s.boss,
];

List<Object?> _rule(SpawnRule r) => [
  r.weight,
  r.biomes,
  r.biomeWeights,
  r.minLight,
  r.maxLight,
  r.group,
  r.place,
  r.maxAlive,
];

List<Object?> _shot(ProjectileSpec p) => [
  p.kind,
  p.speed,
  p.gravity,
  p.damage,
  p.knockback,
  p.radius,
  p.thickness,
  p.length,
  p.color,
  p.glow,
  p.life,
  p.light,
  p.trail,
  p.burns,
  p.onHit,
];

void main() {
  group('MobSpec.copyWith', () {
    test('keeps every field it is not given', () {
      expect(_fields(_full.copyWith()), _fields(_full));
    });

    test('changes the fields it is given and keeps the rest', () {
      final big = _full.copyWith(id: 'big', hp: 80, name: () => 'Big One', spawn: () => const SpawnRule.cave());
      expect((big.id, big.name, big.hp, big.spawn!.place), ('big', 'Big One', 80.0, SpawnPlace.cave));
      expect(_fields(big).skip(3).take(21), _fields(_full).skip(3).take(21));
      expect(_fields(big).skip(25), _fields(_full).skip(25));
    });

    test('a nullable field can be asked for null', () {
      final bare = _full.copyWith(
        name: () => null,
        levels: () => null,
        splitsInto: () => null,
        onHit: () => null,
        mount: () => null,
        fleece: () => null,
        spawn: () => null,
        hurtSound: () => null,
      );
      expect(bare.name, 'Sheep Lord', reason: 'back to the id in title case');
      expect([
        bare.levels,
        bare.splitsInto,
        bare.onHit,
        bare.mount,
        bare.fleece,
        bare.spawn,
        bare.hurtSound,
      ], everyElement(isNull));
      expect(bare.hp, _full.hp);
    });

    test('a name left to the id follows a new id', () {
      expect(const MobSpec('cave_spider').copyWith(id: 'giant_spider').name, 'Giant Spider');
    });
  });

  group('SpawnRule.copyWith', () {
    const rule = SpawnRule(
      weight: 7,
      biomes: ['swamp'],
      biomeWeights: {'swamp': 2.0},
      minLight: 2,
      maxLight: 9,
      group: (2, 4),
      place: SpawnPlace.anywhere,
      maxAlive: 3,
    );

    test('keeps every field it is not given', () {
      expect(_rule(rule.copyWith()), _rule(rule));
    });

    test('changes the fields it is given', () {
      final r = rule.copyWith(weight: 14, group: (1, 1), biomes: () => ['desert']);
      expect(_rule(r), [
        14,
        ['desert'],
        {'swamp': 2.0},
        2,
        9,
        (1, 1),
        SpawnPlace.anywhere,
        3,
      ]);
    });

    test('its biomes can be asked for null: any biome', () {
      expect(rule.copyWith(biomes: () => null).biomes, isNull);
    });
  });

  group('ProjectileSpec.copyWith', () {
    const shot = ProjectileSpec(
      kind: 'frost',
      speed: 20.0,
      gravity: 1.0,
      damage: 5.0,
      knockback: 2.0,
      radius: 0.2,
      thickness: 0.3,
      length: 0.4,
      color: 0x80CCFF,
      glow: true,
      life: 3.0,
      light: 2.0,
      trail: 1.0,
      burns: 1.5,
      onHit: HitEffect('slowness', seconds: 3.0),
    );

    test('keeps every field it is not given', () {
      expect(_shot(shot.copyWith()), _shot(shot));
    });

    test('changes the fields it is given', () {
      final hard = shot.copyWith(damage: 10.0, onHit: () => const HitEffect('poison'));
      expect((hard.damage, hard.onHit!.effect), (10.0, 'poison'));
      expect(_shot(hard).take(3), _shot(shot).take(3));
      expect(_shot(hard).skip(4).take(10), _shot(shot).skip(4).take(10));
    });

    test('its effect on a hit can be asked for null', () {
      expect(shot.copyWith(onHit: () => null).onHit, isNull);
    });
  });

  group('a behaviour copyWith', () {
    test('MeleeAttack keeps what it is not given', () {
      const m = MeleeAttack(priority: 12, damage: 3, reach: 2.0, cooldown: 1.0, knockback: 4.0);
      final c = m.copyWith(damage: 6);
      expect((c.priority, c.damage, c.reach, c.cooldown, c.knockback), (12, 6.0, 2.0, 1.0, 4.0));
      expect(m.copyWith(priority: 3).priority, 3);
    });

    test('RangedAttack keeps what it is not given', () {
      const r = RangedAttack(
        priority: 16,
        projectile: ProjectileSpec.bolt,
        range: 20,
        keepAway: 5,
        holdRange: 11,
        cooldown: 3,
      );
      final c = r.copyWith(projectile: ProjectileSpec.bolt.copyWith(damage: 8.0), cooldown: 1.0);
      expect(
        (c.priority, c.projectile.damage, c.projectile.kind, c.range, c.keepAway, c.holdRange, c.cooldown),
        (16, 8.0, 'bolt', 20.0, 5.0, 11.0, 1.0),
      );
    });

    test('every other behaviour with fields keeps what it is not given', () {
      final w = const Wander(priority: 91, radius: 4.0, speed: 0.3).copyWith(radius: 8.0);
      expect((w.priority, w.radius, w.speed), (91, 8.0, 0.3));
      final h = const Hunt(
        priority: 21,
        range: 9,
        giveUpRange: 18,
        whenProvoked: true,
        prey: ['sheep'],
      ).copyWith(range: 12);
      expect((h.priority, h.range, h.giveUpRange, h.whenProvoked), (21, 12.0, 18.0, true));
      expect(h.prey, ['sheep']);
      final f = const FleeWhenHurt(priority: 6, seconds: 2.0, speed: 1.1).copyWith(seconds: 5.0);
      expect((f.priority, f.seconds, f.speed), (6, 5.0, 1.1));
      final e = const Explode(
        priority: 9,
        trigger: 2.0,
        fuse: 1.0,
        radius: 4.0,
        damage: 10.0,
        breaksBlocks: false,
      ).copyWith(damage: 20.0);
      expect((e.priority, e.trigger, e.fuse, e.radius, e.damage, e.breaksBlocks), (9, 2.0, 1.0, 4.0, 20.0, false));
      final l = const LookAtPlayer(priority: 81, range: 3.0).copyWith(range: 7.0);
      expect((l.priority, l.range), (81, 7.0));
      final p = const PetFight(priority: 22, range: 10.0, giveUpRange: 20.0).copyWith(range: 14.0);
      expect((p.priority, p.range, p.giveUpRange), (22, 14.0, 20.0));
      final he = const Heel(priority: 92, follow: 5.0, stay: 3.0, teleport: 25.0, speed: 0.8).copyWith(stay: 1.0);
      expect((he.priority, he.follow, he.stay, he.teleport, he.speed), (92, 5.0, 1.0, 25.0, 0.8));
      final mw = const MountWait(priority: 93, follow: 3.0, stay: 2.0, leash: 15.0).copyWith(leash: 30.0);
      expect((mw.priority, mw.follow, mw.stay, mw.leash), (93, 3.0, 2.0, 30.0));
    });
  });
}
