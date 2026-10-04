import 'package:voxel_game/voxel_game.dart';

import 'affix.dart';

/// Every creature the game declares: [speciesTable], and an elite of each
/// [Affix] for every one the world spawns but a boss, at [Affix.share] of the
/// spawns among them.
final List<MobSpec> mobTable = [
  for (final s in speciesTable) _elitable(s) ? _copy(s, spawn: _weighed(s.spawn!, _plainWeight)) : s,
  for (final s in speciesTable)
    if (_elitable(s))
      for (final a in Affix.all) _elite(s, a),
];

/// Every creature's kind, by its id: an elite's is the creature it twists
/// (`swift_zombie` is a `zombie`), any other's its own. What a quest and the
/// bestiary count a kill as.
final Map<String, String> plainKinds = {
  for (final s in speciesTable) s.id: s.id,
  for (final s in speciesTable)
    if (_elitable(s))
      for (final a in Affix.all) a.idOf(s.id): s.id,
};

/// Whether the creature [id] is an elite (`Affix`).
bool isElite(String id) => plainKinds[id]! != id;

/// Whether [s] hunts the player unprovoked: a monster.
bool isMonster(MobSpec s) => s.brain.any((b) => b is Hunt && !b.whenProvoked);

/// The 29 creatures, each at the weight it spawns by among the others. A
/// species no spawn rule names is placed by the world's people (VA-Zl): the
/// villager, the temple's and the underworld's lords, a ruin's ghost.
const List<MobSpec> speciesTable = [
  // The farm animals: they wander and run when hurt.
  MobSpec(
    'sheep',
    hp: 8,
    speed: 2.2,
    halfWidth: 0.45,
    height: 1.1,
    rig: Rig.quadruped(body: 0xEBEBE6, head: 0xD9BFA6),
    brain: _grazer,
    loot: LootTable([LootEntry('wool', 1, 2, 1.0), LootEntry('raw_mutton', 1, 2, 1.0)]),
    xp: 3,
    fleece: Fleece('wool'),
    spawn: SpawnRule.daylight(weight: 30, biomes: ['plains', 'forest', 'snow'], group: (1, 3)),
  ),
  MobSpec(
    'cow',
    hp: 12,
    speed: 2.0,
    halfWidth: 0.5,
    height: 1.3,
    rig: Rig.quadruped(body: 0x593826, head: 0xF2E6D9),
    brain: _grazer,
    loot: LootTable([LootEntry('leather', 1, 2, 1.0), LootEntry('raw_beef', 1, 3, 1.0)]),
    xp: 4,
    yields: {'bucket': 'milk_bucket'},
    spawn: SpawnRule.daylight(weight: 22, biomes: ['plains', 'forest'], group: (1, 3)),
  ),
  MobSpec(
    'pig',
    hp: 10,
    speed: 2.4,
    halfWidth: 0.45,
    height: 0.9,
    rig: Rig.quadruped(body: 0xF2A6B3, head: 0xD9808C),
    brain: _grazer,
    loot: LootTable([LootEntry('raw_pork', 1, 3, 1.0)]),
    xp: 3,
    spawn: SpawnRule.daylight(weight: 20, biomes: ['plains', 'forest', 'swamp'], group: (1, 3)),
  ),
  MobSpec(
    'chicken',
    hp: 4,
    speed: 2.6,
    halfWidth: 0.25,
    height: 0.6,
    rig: Rig.bird(body: 0xF2F2EB, feathers: 0xE64D33),
    brain: _grazer,
    loot: LootTable([LootEntry('raw_chicken', 1, 1, 1.0), LootEntry('feather', 1, 3, 1.0)]),
    xp: 2,
    spawn: SpawnRule.daylight(weight: 18, biomes: ['plains', 'forest', 'swamp'], group: (1, 3)),
  ),
  // A wolf keeps to itself until hurt; a bone tames it, half the time, into a companion that heels and fights.
  MobSpec(
    'wolf',
    hp: 14,
    speed: 5.2,
    halfWidth: 0.4,
    height: 0.95,
    rig: Rig.quadruped(body: 0x8C8C94, head: 0x595961),
    brain: [
      MeleeAttack(damage: 4, reach: _reach, cooldown: _swing),
      _provoked,
      Wander(),
    ],
    loot: LootTable([LootEntry('bone', 0, 1, 1.0)]),
    xp: 8,
    tameWith: ['bone'],
    tameChance: 0.5,
    tamedBrain: [
      MeleeAttack(damage: 4, reach: _reach, cooldown: _swing),
      PetFight(),
      Heel(),
    ],
    spawn: SpawnRule.daylight(weight: 8, biomes: ['forest', 'snow', 'mountain'], group: (1, 3)),
  ),
  // A horse: wheat or an apple tames it, and then a use rides it.
  MobSpec(
    'horse',
    hp: 20,
    speed: 8.5,
    halfWidth: 0.5,
    height: 1.6,
    rig: Rig.quadruped(body: 0x734726, head: 0x261F1A),
    brain: _grazer,
    loot: LootTable([LootEntry('leather', 1, 2, 1.0)]),
    xp: 5,
    tameWith: ['wheat', 'apple'],
    tameChance: 0.6,
    tamedBrain: [MountWait()],
    mount: MountSpec(seat: 1.0),
    spawn: SpawnRule.daylight(weight: 10, biomes: ['plains', 'forest'], group: (1, 3)),
  ),
  // The night's: in the dark of the surface and of the caves, tougher as the player grows.
  MobSpec(
    'zombie',
    hp: 18,
    speed: 2.6,
    rig: Rig.humanoid(skin: 0x66A666, shirt: 0x4073A6, pants: 0x404D59, armsForward: true, redEyes: true),
    brain: [
      MeleeAttack(damage: 4, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('rotten_flesh', 0, 2, 1.0), LootEntry('magic_dust', 0, 1, 1.0)]),
    xp: 12,
    levels: _levels,
    burnsInDaylight: true,
    spawn: SpawnRule.dark(weight: 30, biomes: _surface),
  ),
  MobSpec(
    'skeleton',
    hp: 14,
    speed: 2.8,
    rig: Rig.humanoid(skin: 0xE0DBC7, shirt: 0xCCC7B3, pants: 0xCCC7B3, redEyes: true),
    brain: [_Volley.arrow, _hunt, Wander()],
    loot: LootTable([LootEntry('bone', 1, 3, 1.0), LootEntry('arrow', 0, 4, 1.0), LootEntry('gunpowder', 0, 1, 1.0)]),
    xp: 14,
    levels: _levels,
    burnsInDaylight: true,
    spawn: SpawnRule.dark(weight: 22, biomes: _surface),
  ),
  // A spider's bite poisons; a swamp night crawls with them.
  MobSpec(
    'spider',
    hp: 12,
    speed: 4.6,
    halfWidth: 0.6,
    height: 0.7,
    rig: Rig.spider(body: 0x332E33, eyes: 0xBF2626),
    brain: [
      MeleeAttack(damage: 3, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('string', 1, 3, 1.0), LootEntry('spider_eye', 0, 1, 1.0)]),
    xp: 10,
    levels: _levels,
    onHit: HitEffect('poison', seconds: Affix.seconds),
    spawn: SpawnRule.dark(
      weight: 18,
      biomes: ['plains', 'forest', 'desert', 'swamp', 'jungle'],
      biomeWeights: {'swamp': 2.5},
    ),
  ),
  // A slime dies into two small ones; the swamp is full of them.
  MobSpec(
    'slime',
    hp: 12,
    speed: 3.0,
    halfWidth: 0.5,
    height: 1.0,
    rig: Rig.blob(color: 0x73D966),
    gait: Gait.hop,
    brain: [
      MeleeAttack(damage: 2, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('slime_ball', 1, 3, 1.0)]),
    xp: 6,
    levels: _levels,
    splitsInto: MobSplit('slime_small'),
    spawn: SpawnRule.dark(weight: 14, biomes: ['plains', 'forest', 'swamp'], biomeWeights: {'swamp': 2.5}),
  ),
  MobSpec(
    'slime_small',
    name: 'Small Slime',
    hp: 4,
    speed: 3.4,
    halfWidth: 0.28,
    height: 0.55,
    rig: Rig.blob(color: 0x8CEB7A),
    gait: Gait.hop,
    brain: [
      MeleeAttack(damage: 1, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('slime_ball', 0, 1, 1.0)]),
    xp: 2,
    levels: _levels,
  ),
  // The caves' own.
  MobSpec(
    'cave_slime',
    hp: 16,
    speed: 3.2,
    halfWidth: 0.55,
    height: 1.1,
    rig: Rig.blob(color: 0x598CD9),
    gait: Gait.hop,
    brain: [
      MeleeAttack(damage: 3, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('slime_ball', 1, 3, 1.0), LootEntry('gem_shard', 0, 1, 1.0)]),
    xp: 9,
    levels: _levels,
    spawn: SpawnRule.cave(weight: 20),
  ),
  MobSpec(
    'troll',
    name: 'Cave Troll',
    hp: 60,
    speed: 2.2,
    halfWidth: 0.55,
    height: 2.8,
    rig: Rig.humanoid(skin: 0x738066, shirt: 0x594D40, pants: 0x4D4033, armsForward: true, redEyes: true),
    brain: [
      MeleeAttack(damage: 9, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([
      LootEntry('gem_shard', 1, 3, 1.0),
      LootEntry('magic_dust', 1, 2, 1.0),
      LootEntry('gold_ingot', 0, 2, 1.0),
    ]),
    xp: 60,
    levels: _levels,
    spawn: SpawnRule.cave(weight: 3),
  ),
  // The snow's: a wisp of frost that keeps its distance and throws ice.
  MobSpec(
    'snow_golem',
    name: 'Frost Wisp',
    hp: 16,
    speed: 3.4,
    halfWidth: 0.4,
    height: 0.9,
    rig: Rig.blob(color: 0xBFE6FF),
    brain: [_Volley.frost, _hunt, Wander()],
    loot: LootTable([LootEntry('magic_dust', 1, 2, 1.0)]),
    xp: 16,
    levels: _levels,
    spawn: SpawnRule.dark(weight: 12, biomes: ['snow', 'mountain']),
  ),
  // A boomer swells beside its target and bursts.
  MobSpec(
    'boomer',
    hp: 12,
    speed: 3.4,
    halfWidth: 0.35,
    height: 1.2,
    rig: Rig.blob(color: 0x59BF4D),
    brain: [
      Explode(trigger: _reach + 0.35, fuse: 1.1, radius: 3.0, damage: 10.0),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('gunpowder', 1, 3, 1.0)]),
    xp: 10,
    levels: _levels,
    spawn: SpawnRule.dark(weight: 12, biomes: ['plains', 'forest', 'desert', 'swamp']),
  ),
  // Two bosses the night brings, one at a time: their health is a bar at the top while they are about.
  MobSpec(
    'yeti',
    hp: 90,
    speed: 3.6,
    halfWidth: 0.6,
    height: 3.0,
    rig: Rig.humanoid(skin: 0xEBF0FA, shirt: 0xD9E0F2, pants: 0xBFC7D9, redEyes: true),
    brain: [
      MeleeAttack(damage: 10, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([
      LootEntry('magic_dust', 2, 4, 1.0),
      LootEntry('diamond', 1, 2, 1.0),
      LootEntry('gem_shard', 2, 4, 1.0),
      _bossDiamond,
    ]),
    xp: 120,
    levels: _levels,
    spawn: SpawnRule.dark(weight: 2, biomes: ['snow', 'mountain'], maxAlive: 1),
    boss: true,
  ),
  MobSpec(
    'scorpion_king',
    hp: 80,
    speed: 4.6,
    halfWidth: 1.0,
    height: 1.2,
    rig: Rig.spider(body: 0x8C5926, eyes: 0xF2401A),
    brain: [
      MeleeAttack(damage: 9, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([
      LootEntry('gold_ingot', 2, 4, 1.0),
      LootEntry('gem_shard', 2, 5, 1.0),
      LootEntry('diamond', 0, 2, 1.0),
      _bossDiamond,
    ]),
    xp: 110,
    levels: _levels,
    onHit: HitEffect('poison', seconds: Affix.seconds),
    spawn: SpawnRule.dark(weight: 2, biomes: ['desert'], maxAlive: 1),
    boss: true,
  ),
  // A villager strolls within 16 m of its village's centre (its home, `Villages`), is never forgotten and takes no
  // harm; its use opens its trades.
  MobSpec(
    'villager',
    hp: 20,
    speed: 1.8,
    height: 1.75,
    rig: Rig.humanoid(skin: 0xEBBF9E, shirt: 0x8C66A6, pants: 0x594D40),
    brain: [Wander(radius: 16.0)],
    persistent: true,
    invulnerable: true,
  ),
  // The jungle's: a parrot that seeds tame, and a quick ocelot that bites back.
  MobSpec(
    'parrot',
    hp: 6,
    speed: 4.0,
    halfWidth: 0.2,
    height: 0.45,
    rig: Rig.bird(body: 0xE63340, feathers: 0x408CF2),
    gait: Gait.fly,
    brain: _grazer,
    loot: LootTable([LootEntry('feather', 1, 2, 1.0)]),
    xp: 2,
    tameWith: ['wheat_seeds'],
    tameChance: 0.5,
    tamedBrain: [Heel()],
    spawn: SpawnRule.daylight(weight: 14, biomes: ['jungle'], group: (1, 3)),
  ),
  MobSpec(
    'ocelot',
    hp: 10,
    speed: 6.8,
    halfWidth: 0.3,
    height: 0.7,
    rig: Rig.quadruped(body: 0xD9A64D, head: 0x594026),
    brain: [
      MeleeAttack(damage: 3, reach: _reach, cooldown: _swing),
      _provoked,
      Wander(),
    ],
    loot: LootTable([LootEntry('string', 0, 1, 1.0)]),
    xp: 6,
    spawn: SpawnRule.daylight(weight: 8, biomes: ['jungle'], group: (1, 3)),
  ),
  // The desert temple's boss: its touch slows. Kept by the save, which wakes it once (`Structures`).
  MobSpec(
    'mummy_king',
    hp: 120,
    speed: 1.8,
    halfWidth: 0.4,
    height: 2.2,
    rig: Rig.humanoid(skin: 0xD9CCA6, shirt: 0xBFB38C, pants: 0x998C66, armsForward: true, redEyes: true),
    brain: [
      MeleeAttack(damage: 7, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('gold_ingot', 2, 5, 1.0), LootEntry('ancient_blade', 1, 1, 1.0), _bossDiamond]),
    xp: 48,
    levels: _levels,
    onHit: HitEffect('slow', seconds: Affix.seconds),
    persistent: true,
    boss: true,
  ),
  MobSpec(
    'bat',
    hp: 4,
    speed: 4.2,
    halfWidth: 0.2,
    height: 0.4,
    rig: Rig.bird(body: 0x332938, feathers: 0x8C3340),
    gait: Gait.fly,
    brain: [
      MeleeAttack(damage: 1, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('leather', 0, 1, 1.0)]),
    xp: 3,
    levels: _levels,
    spawn: SpawnRule.cave(weight: 14),
  ),
  MobSpec(
    'bear',
    hp: 40,
    speed: 4.5,
    halfWidth: 0.55,
    height: 1.5,
    rig: Rig.quadruped(body: 0x614229, head: 0x472E1A),
    brain: [
      MeleeAttack(damage: 6, reach: _reach, cooldown: _swing),
      _provoked,
      Wander(),
    ],
    loot: LootTable([LootEntry('leather', 1, 3, 1.0), LootEntry('raw_beef', 1, 2, 1.0)]),
    xp: 18,
    spawn: SpawnRule.daylight(weight: 5, biomes: ['forest'], group: (1, 3)),
  ),
  // A ruin's ghost drifts through walls; its touch slows.
  MobSpec(
    'ghost',
    hp: 15,
    speed: 2.4,
    rig: Rig.humanoid(skin: 0xCCE0F2, shirt: 0xB3CCEB, pants: 0x99B3D9, redEyes: true),
    gait: Gait.fly,
    ghost: true,
    brain: [
      MeleeAttack(damage: 3, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('magic_dust', 1, 2, 1.0)]),
    xp: 14,
    levels: _levels,
    onHit: HitEffect('slow', seconds: Affix.seconds),
  ),
  // The desert's, in its shade by day: its sting poisons.
  MobSpec(
    'scorpion',
    hp: 14,
    speed: 4.0,
    halfWidth: 0.5,
    height: 0.6,
    rig: Rig.spider(body: 0xA67333, eyes: 0x59331A),
    brain: [
      MeleeAttack(damage: 5, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('gem_shard', 0, 1, 1.0), LootEntry('string', 0, 2, 1.0)]),
    xp: 12,
    levels: _levels,
    onHit: HitEffect('poison', seconds: Affix.seconds),
    spawn: SpawnRule(weight: 10, biomes: ['desert'], maxLight: 7),
  ),
  // The underworld's: a blaze throws fire, a dark skeleton withers, a magma cube burns.
  MobSpec(
    'blaze',
    hp: 20,
    speed: 3.6,
    halfWidth: 0.35,
    height: 0.9,
    rig: Rig.blob(color: 0xF2A633),
    gait: Gait.fly,
    brain: [_Volley.blazeFire, _hunt, Wander()],
    loot: LootTable([LootEntry('blaze_rod', 0, 2, 1.0), LootEntry('glowstone_dust', 0, 1, 1.0)]),
    xp: 18,
    levels: _levels,
    spawn: SpawnRule.dark(weight: 16, biomes: ['underworld']),
  ),
  MobSpec(
    'dark_skeleton',
    name: 'Wither Skeleton',
    hp: 30,
    speed: 3.0,
    height: 2.0,
    rig: Rig.humanoid(skin: 0x332E33, shirt: 0x262126, pants: 0x1F1A1F, redEyes: true),
    brain: [
      MeleeAttack(damage: 5, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('bone', 1, 3, 1.0), LootEntry('coal', 0, 2, 1.0), LootEntry('quartz', 0, 1, 1.0)]),
    xp: 22,
    levels: _levels,
    burnsInDaylight: true,
    onHit: HitEffect('wither', seconds: Affix.seconds),
    spawn: SpawnRule.dark(weight: 14, biomes: ['underworld']),
  ),
  MobSpec(
    'magma_cube',
    hp: 16,
    speed: 3.0,
    halfWidth: 0.5,
    height: 1.0,
    rig: Rig.blob(color: 0x8C2E1A),
    gait: Gait.hop,
    brain: [
      MeleeAttack(damage: 3, reach: _reach, cooldown: _swing),
      _hunt,
      Wander(),
    ],
    loot: LootTable([LootEntry('blaze_rod', 0, 1, 1.0), LootEntry('magic_dust', 0, 1, 1.0)]),
    xp: 12,
    levels: _levels,
    onHit: HitEffect('burning', seconds: Affix.seconds),
    spawn: SpawnRule.dark(weight: 14, biomes: ['underworld']),
  ),
  // The fortress's lord: it flies and throws fire. The heart is not its drop but the fortress core's, which his
  // death unseals; kept by the save, or a lord lost to it would leave the core sealed for good.
  MobSpec(
    'underworld_lord',
    hp: 200,
    speed: 3.2,
    halfWidth: 0.6,
    height: 3.2,
    rig: Rig.humanoid(skin: 0x4D141F, shirt: 0x8C1F1A, pants: 0x330F14, redEyes: true),
    gait: Gait.fly,
    brain: [_Volley.lordFire, _hunt, Wander()],
    loot: LootTable([LootEntry('blaze_rod', 8, 8, 1.0), LootEntry('ancient_blade', 1, 1, 1.0), _bossDiamond]),
    xp: 300,
    levels: _levels,
    persistent: true,
    boss: true,
  ),
];

/// The weight a spawn rule's own kind keeps, of the 75 parts its weight is cut
/// into: the other six go one to each elite (6 / 75 = [Affix.share]).
const int _plainWeight = 69;

/// Whether the world spawns elites of [s]: a creature it spawns that is no boss.
bool _elitable(MobSpec s) => s.spawn != null && !s.boss;

MobSpec _elite(MobSpec s, Affix a) => _copy(
  s,
  id: a.idOf(s.id),
  name: '${a.name} ${s.name}',
  hp: s.hp * a.hp,
  speed: s.speed * a.speed,
  halfWidth: s.halfWidth * a.scale,
  height: s.height * a.scale,
  brain: [for (final b in s.brain) _harder(b, a.damage)],
  loot: LootTable([...s.loot.entries, ...Affix.loot]),
  xp: (s.xp * Affix.xp).round(),
  onHit: a.effect == null ? s.onHit : HitEffect(a.effect!, seconds: Affix.seconds),
  spawn: SpawnRule(
    weight: s.spawn!.weight,
    biomes: s.spawn!.biomes,
    biomeWeights: s.spawn!.biomeWeights,
    minLight: s.spawn!.minLight,
    maxLight: s.spawn!.maxLight,
    place: s.spawn!.place,
    maxAlive: s.spawn!.maxAlive,
  ),
);

/// [b] striking [times] as hard.
Behavior _harder(Behavior b, double times) => switch (b) {
  MeleeAttack() => MeleeAttack(
    priority: b.priority,
    damage: b.damage * times,
    reach: b.reach,
    cooldown: b.cooldown,
    knockback: b.knockback,
  ),
  RangedAttack() => RangedAttack(
    priority: b.priority,
    projectile: _Volley.shot(b.projectile, damage: b.projectile.damage * times),
    range: b.range,
    keepAway: b.keepAway,
    holdRange: b.holdRange,
    cooldown: b.cooldown,
  ),
  _ => b,
};

SpawnRule _weighed(SpawnRule r, int times) => SpawnRule(
  weight: r.weight * times,
  biomes: r.biomes,
  biomeWeights: r.biomeWeights,
  minLight: r.minLight,
  maxLight: r.maxLight,
  group: r.group,
  place: r.place,
  maxAlive: r.maxAlive,
);

/// [s] with the given fields replaced.
MobSpec _copy(
  MobSpec s, {
  String? id,
  String? name,
  double? hp,
  double? speed,
  double? halfWidth,
  double? height,
  List<Behavior>? brain,
  LootTable? loot,
  int? xp,
  HitEffect? onHit,
  SpawnRule? spawn,
}) => MobSpec(
  id ?? s.id,
  name: name ?? s.name,
  hp: hp ?? s.hp,
  speed: speed ?? s.speed,
  halfWidth: halfWidth ?? s.halfWidth,
  height: height ?? s.height,
  rig: s.rig,
  gait: s.gait,
  brain: brain ?? s.brain,
  loot: loot ?? s.loot,
  xp: xp ?? s.xp,
  levels: s.levels,
  burnsInDaylight: s.burnsInDaylight,
  splitsInto: s.splitsInto,
  onHit: onHit ?? s.onHit,
  tameWith: s.tameWith,
  tameChance: s.tameChance,
  tamedBrain: s.tamedBrain,
  mount: s.mount,
  yields: s.yields,
  fleece: s.fleece,
  persistent: s.persistent,
  ghost: s.ghost,
  spawn: spawn ?? s.spawn,
  knockbackResistance: s.knockbackResistance,
  hurtSound: s.hurtSound,
  boss: s.boss,
);

/// A farm animal's mind: it runs when hurt, else wanders.
const List<Behavior> _grazer = [FleeWhenHurt(), Wander()];

/// Every biome of the overworld's land and shore: where the night's walk.
const List<String> _surface = ['beach', 'frozen_shore', 'plains', 'forest', 'desert', 'snow', 'mountain', 'swamp'];

/// A hostile notices the player 18 m off and gives up 2.2 times as far.
const Hunt _hunt = Hunt(range: 18.0, giveUpRange: 39.6);

/// A neutral creature goes only after whoever hurt it.
const Hunt _provoked = Hunt(range: 18.0, giveUpRange: 39.6, whenProvoked: true);

/// How far a blow reaches past a body's half width, and the seconds between two.
const double _reach = 1.9, _swing = 1.3;

/// A hostile grows with the player: health, blows and worth.
const MobLevels _levels = MobLevels(hp: 0.18, damage: 0.12, xp: 0.15);

/// A boss always drops a diamond.
const LootEntry _bossDiamond = LootEntry('diamond', 1, 1, 1.0);

/// What a creature that keeps its distance shoots: inside 6 m it backs off,
/// inside 13 m it holds, and within 16 m it shoots every 2.2 s.
abstract final class _Volley {
  static const RangedAttack arrow = RangedAttack(
    projectile: ProjectileSpec(speed: 24.0, gravity: 14.0, damage: 3.0, knockback: 5.0, radius: 0.1),
    range: 16.0,
    keepAway: 6.0,
    holdRange: 13.0,
    cooldown: 2.2,
  );

  static const RangedAttack frost = RangedAttack(
    projectile: ProjectileSpec(
      kind: 'frost',
      speed: 24.0,
      gravity: 0.0,
      damage: 3.0,
      knockback: 5.0,
      radius: 0.1,
      thickness: 0.2,
      length: 0.2,
      color: 0x80CCFF,
      glow: true,
      light: 4.0,
      trail: 1.2,
    ),
    range: 16.0,
    keepAway: 6.0,
    holdRange: 13.0,
    cooldown: 2.2,
  );

  static const RangedAttack blazeFire = RangedAttack(
    projectile: _fire3,
    range: 16.0,
    keepAway: 6.0,
    holdRange: 13.0,
    cooldown: 2.2,
  );

  static const RangedAttack lordFire = RangedAttack(
    projectile: ProjectileSpec(
      kind: 'fire',
      speed: 24.0,
      gravity: 0.0,
      damage: 8.0,
      knockback: 5.0,
      radius: 0.25,
      thickness: 0.4,
      length: 0.4,
      color: 0xFF590D,
      glow: true,
      light: 4.0,
      trail: 1.6,
      burns: 4.0,
      onHit: HitEffect('burning', seconds: 4.0),
    ),
    range: 16.0,
    keepAway: 6.0,
    holdRange: 13.0,
    cooldown: 2.2,
  );

  static const ProjectileSpec _fire3 = ProjectileSpec(
    kind: 'fire',
    speed: 24.0,
    gravity: 0.0,
    damage: 3.0,
    knockback: 5.0,
    radius: 0.25,
    thickness: 0.4,
    length: 0.4,
    color: 0xFF590D,
    glow: true,
    light: 4.0,
    trail: 1.6,
    burns: 4.0,
    onHit: HitEffect('burning', seconds: 4.0),
  );

  /// [p] dealing [damage].
  static ProjectileSpec shot(ProjectileSpec p, {required double damage}) => ProjectileSpec(
    kind: p.kind,
    speed: p.speed,
    gravity: p.gravity,
    damage: damage,
    knockback: p.knockback,
    radius: p.radius,
    thickness: p.thickness,
    length: p.length,
    color: p.color,
    glow: p.glow,
    life: p.life,
    light: p.light,
    trail: p.trail,
    burns: p.burns,
    onHit: p.onHit,
  );
}
