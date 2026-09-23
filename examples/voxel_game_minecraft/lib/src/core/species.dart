import 'dart:math';

import 'package:vector_math/vector_math.dart';

/// Creature table: stats, behaviour, drops and the voxel model recipe.
/// body: "quadruped" | "humanoid" | "blob" | "spider" | "bird"
class SpeciesDef {
  SpeciesDef({
    required this.id,
    required this.name,
    required this.hp,
    required this.damage,
    required this.speed,
    required this.hostile,
    required this.xp,
    required this.body,
    required this.halfWidth,
    required this.height,
    required this.colors,
    required this.drops,
    required this.biomes,
    required this.day,
    required this.weight,
    this.neutral = false,
    this.ranged = false,
    this.hops = false,
    this.explodes = false,
    this.boss = false,
    this.trader = false,
    this.cave = false,
    this.effect = '',
    this.mount = false,
    this.tameWith = const [],
    this.tameChance = 0.0,
    this.flying = false,
    this.ghost = false,
    this.biomeWeight = const {},
    this.splits = '',
    this.persistent = false,
    this.projectile = '',
    this.volley = 0,
  });

  /// Stage 29: the kind of shot a ranged creature fires ("fire" sets the target
  /// burning) and the bolts in a boss's volley. Data only, as in Godot: the
  /// ranged AI still picks arrow / frost by body.
  final String projectile;
  final int volley;

  /// Stage 26: a multiplier on [weight] per biome (a swamp night crawls with
  /// spiders and slimes).
  final Map<int, double> biomeWeight;

  /// Stage 26: the species this one splits into (two of them) the first time it
  /// dies ("" for none).
  final String splits;

  /// Stage 26: never despawns and rides the save (a villager).
  final bool persistent;

  final String id;
  final String name;
  final double hp;
  final double damage;
  final double speed;
  final bool hostile;
  final bool neutral;
  final bool ranged;
  final bool hops;
  final bool explodes;
  final bool boss;
  final bool trader;
  final bool cave;

  /// The status effect this species inflicts on a hit ("" for none).
  final String effect;

  /// Whether this creature can be ridden once tamed.
  final bool mount;

  /// The items that tame it, and the chance one attempt works.
  final List<String> tameWith;
  final double tameChance;

  /// Stage 23: no gravity, a fluttering 3D heading (bat, ghost).
  final bool flying;

  /// Stage 23: passes through blocks and draws translucent.
  final bool ghost;

  /// Stage 23: a cave spawn only at or below this height.
  final int xp;
  final String body;
  final double halfWidth;
  final double height;
  final List<Vector3> colors;

  /// item id -> [min, max]
  final Map<String, List<int>> drops;
  final List<int> biomes;
  final bool day;
  final double weight;
}

Vector3 _c(double r, double g, double b) => Vector3(r, g, b);

class Species {
  Species._();

  static final Map<String, SpeciesDef> defs = _build();

  static Map<String, SpeciesDef> _build() {
    final out = <String, SpeciesDef>{};
    void s(SpeciesDef d) => out[d.id] = d;
    s(SpeciesDef(id: 'sheep', name: 'Sheep', hp: 8, damage: 0, speed: 2.2, hostile: false, xp: 3, body: 'quadruped',
        halfWidth: 0.45, height: 1.1, colors: [_c(0.92, 0.92, 0.90), _c(0.85, 0.75, 0.65)],
        drops: {'wool': [1, 2], 'raw_mutton': [1, 2]}, biomes: [2, 3, 5], day: true, weight: 30));
    s(SpeciesDef(id: 'cow', name: 'Cow', hp: 12, damage: 0, speed: 2.0, hostile: false, xp: 4, body: 'quadruped',
        halfWidth: 0.5, height: 1.3, colors: [_c(0.35, 0.22, 0.15), _c(0.95, 0.90, 0.85)],
        drops: {'leather': [1, 2], 'raw_beef': [1, 3]}, biomes: [2, 3], day: true, weight: 22));
    s(SpeciesDef(id: 'pig', name: 'Pig', hp: 10, damage: 0, speed: 2.4, hostile: false, xp: 3, body: 'quadruped',
        halfWidth: 0.45, height: 0.9, colors: [_c(0.95, 0.65, 0.70), _c(0.85, 0.50, 0.55)],
        drops: {'raw_pork': [1, 3]}, biomes: [2, 3, 7], day: true, weight: 20));
    s(SpeciesDef(id: 'chicken', name: 'Chicken', hp: 4, damage: 0, speed: 2.6, hostile: false, xp: 2, body: 'bird',
        halfWidth: 0.25, height: 0.6, colors: [_c(0.95, 0.95, 0.92), _c(0.9, 0.3, 0.2)],
        drops: {'raw_chicken': [1, 1], 'feather': [1, 3]}, biomes: [2, 3, 7], day: true, weight: 18));
    s(SpeciesDef(id: 'wolf', name: 'Wolf', hp: 14, damage: 4, speed: 5.2, hostile: false, neutral: true, xp: 8, body: 'quadruped',
        halfWidth: 0.4, height: 0.95, colors: [_c(0.55, 0.55, 0.58), _c(0.35, 0.35, 0.38)],
        drops: {'bone': [0, 1]}, biomes: [3, 5, 6], day: true, weight: 8, tameWith: ['bone'], tameChance: 0.5));
    s(SpeciesDef(id: 'horse', name: 'Horse', hp: 20, damage: 0, speed: 8.5, hostile: false, xp: 5, body: 'quadruped',
        halfWidth: 0.5, height: 1.6, colors: [_c(0.45, 0.28, 0.15), _c(0.15, 0.12, 0.10)],
        drops: {'leather': [1, 2]}, biomes: [2, 3], day: true, weight: 10, mount: true,
        tameWith: ['wheat', 'apple'], tameChance: 0.6));
    s(SpeciesDef(id: 'zombie', name: 'Zombie', hp: 18, damage: 4, speed: 2.6, hostile: true, xp: 12, body: 'humanoid',
        halfWidth: 0.3, height: 1.8, colors: [_c(0.40, 0.65, 0.40), _c(0.25, 0.45, 0.65), _c(0.25, 0.30, 0.35)],
        drops: {'rotten_flesh': [0, 2], 'magic_dust': [0, 1]}, biomes: [1, 2, 3, 4, 5, 6, 7], day: false, weight: 30));
    s(SpeciesDef(id: 'skeleton', name: 'Skeleton', hp: 14, damage: 3, speed: 2.8, hostile: true, ranged: true, xp: 14, body: 'humanoid',
        halfWidth: 0.3, height: 1.8, colors: [_c(0.88, 0.86, 0.78), _c(0.80, 0.78, 0.70), _c(0.80, 0.78, 0.70)],
        drops: {'bone': [1, 3], 'arrow': [0, 4], 'gunpowder': [0, 1]}, biomes: [1, 2, 3, 4, 5, 6, 7], day: false, weight: 22));
    s(SpeciesDef(id: 'spider', name: 'Spider', hp: 12, damage: 3, speed: 4.6, hostile: true, xp: 10, body: 'spider',
        halfWidth: 0.6, height: 0.7, colors: [_c(0.20, 0.18, 0.20), _c(0.75, 0.15, 0.15)],
        drops: {'string': [1, 3], 'spider_eye': [0, 1]}, biomes: [2, 3, 4, 7, 8], day: false, weight: 18, effect: 'poison',
        biomeWeight: {7: 2.5})); // stage 26: a swamp night crawls with them
    // Stage 26: the slime splits into two small slimes the first time it dies.
    s(SpeciesDef(id: 'slime', name: 'Slime', hp: 12, damage: 2, speed: 3.0, hostile: true, hops: true, xp: 6, body: 'blob',
        halfWidth: 0.5, height: 1.0, colors: [_c(0.45, 0.85, 0.40)], drops: {'slime_ball': [1, 3]},
        biomes: [2, 3, 7], day: false, weight: 14, biomeWeight: {7: 2.5}, splits: 'slime_small'));
    s(SpeciesDef(id: 'slime_small', name: 'Small Slime', hp: 4, damage: 1, speed: 3.4, hostile: true, hops: true, xp: 2, body: 'blob',
        halfWidth: 0.28, height: 0.55, colors: [_c(0.55, 0.92, 0.48)], drops: {'slime_ball': [0, 1]},
        biomes: [], day: false, weight: 0));
    s(SpeciesDef(id: 'cave_slime', name: 'Cave Slime', hp: 16, damage: 3, speed: 3.2, hostile: true, hops: true, xp: 9, body: 'blob',
        halfWidth: 0.55, height: 1.1, colors: [_c(0.35, 0.55, 0.85)], drops: {'slime_ball': [1, 3], 'gem_shard': [0, 1]},
        biomes: [], cave: true, day: true, weight: 20));
    s(SpeciesDef(id: 'troll', name: 'Cave Troll', hp: 60, damage: 9, speed: 2.2, hostile: true, xp: 60, body: 'humanoid',
        halfWidth: 0.55, height: 2.8, colors: [_c(0.45, 0.50, 0.40), _c(0.35, 0.30, 0.25), _c(0.30, 0.25, 0.20)],
        drops: {'gem_shard': [1, 3], 'magic_dust': [1, 2], 'gold_ingot': [0, 2]}, biomes: [], cave: true, day: true, weight: 3));
    s(SpeciesDef(id: 'snow_golem', name: 'Frost Wisp', hp: 16, damage: 3, speed: 3.4, hostile: true, ranged: true, xp: 16, body: 'blob',
        halfWidth: 0.4, height: 0.9, colors: [_c(0.75, 0.90, 1.0)], drops: {'magic_dust': [1, 2]},
        biomes: [5, 6], day: false, weight: 12));
    s(SpeciesDef(id: 'boomer', name: 'Boomer', hp: 12, damage: 0, speed: 3.4, hostile: true, xp: 10, body: 'blob', explodes: true,
        halfWidth: 0.35, height: 1.2, colors: [_c(0.35, 0.75, 0.30)], drops: {'gunpowder': [1, 3]},
        biomes: [2, 3, 4, 7], day: false, weight: 12));
    s(SpeciesDef(id: 'yeti', name: 'Yeti', hp: 90, damage: 10, speed: 3.6, hostile: true, xp: 120, body: 'humanoid', boss: true,
        halfWidth: 0.6, height: 3.0, colors: [_c(0.92, 0.94, 0.98), _c(0.85, 0.88, 0.95), _c(0.75, 0.78, 0.85)],
        drops: {'magic_dust': [2, 4], 'diamond': [1, 2], 'gem_shard': [2, 4]}, biomes: [5, 6], day: false, weight: 2));
    s(SpeciesDef(id: 'scorpion_king', name: 'Scorpion King', hp: 80, damage: 9, speed: 4.6, hostile: true, xp: 110, body: 'spider', boss: true,
        halfWidth: 1.0, height: 1.2, colors: [_c(0.55, 0.35, 0.15), _c(0.95, 0.25, 0.10)],
        drops: {'gold_ingot': [2, 4], 'gem_shard': [2, 5], 'diamond': [0, 2]}, biomes: [4], day: false, weight: 2, effect: 'poison'));
    s(SpeciesDef(id: 'villager', name: 'Villager', hp: 20, damage: 0, speed: 1.8, hostile: false, xp: 0, body: 'humanoid',
        halfWidth: 0.3, height: 1.75, colors: [_c(0.92, 0.75, 0.62), _c(0.55, 0.40, 0.65), _c(0.35, 0.30, 0.25)],
        drops: {}, biomes: [], day: true, weight: 0, trader: true, persistent: true));
    // Stage 26: the jungle's parrot (passive flier, tamed with seeds) and ocelot
    // (neutral, fast).
    s(SpeciesDef(id: 'parrot', name: 'Parrot', hp: 6, damage: 0, speed: 4.0, hostile: false, xp: 2, body: 'bird', flying: true,
        halfWidth: 0.2, height: 0.45, colors: [_c(0.90, 0.20, 0.25), _c(0.25, 0.55, 0.95)],
        drops: {'feather': [1, 2]}, biomes: [8], day: true, weight: 14, tameWith: ['wheat_seeds'], tameChance: 0.5));
    s(SpeciesDef(id: 'ocelot', name: 'Ocelot', hp: 10, damage: 3, speed: 6.8, hostile: false, neutral: true, xp: 6, body: 'quadruped',
        halfWidth: 0.3, height: 0.7, colors: [_c(0.85, 0.65, 0.30), _c(0.35, 0.25, 0.15)],
        drops: {'string': [0, 1]}, biomes: [8], day: true, weight: 8));
    // Stage 23: the desert temple boss (spawned by `Game._checkStructures`, never
    // by the spawner), a cave bat, a forest bear and a ruin ghost.
    s(SpeciesDef(id: 'mummy_king', name: 'Mummy King', hp: 120, damage: 7, speed: 1.8, hostile: true, xp: 48, body: 'humanoid', boss: true,
        halfWidth: 0.4, height: 2.2, colors: [_c(0.85, 0.80, 0.65), _c(0.75, 0.70, 0.55), _c(0.60, 0.55, 0.40)],
        drops: {'gold_ingot': [2, 5], 'ancient_blade': [1, 1]}, biomes: [], day: false, weight: 0, effect: 'slow'));
    s(SpeciesDef(id: 'bat', name: 'Bat', hp: 4, damage: 1, speed: 4.2, hostile: true, xp: 3, body: 'bird', flying: true,
        halfWidth: 0.2, height: 0.4, colors: [_c(0.20, 0.16, 0.22), _c(0.55, 0.20, 0.25)],
        drops: {'leather': [0, 1]}, biomes: [], cave: true, day: true, weight: 14));
    s(SpeciesDef(id: 'bear', name: 'Bear', hp: 40, damage: 6, speed: 4.5, hostile: false, neutral: true, xp: 18, body: 'quadruped',
        halfWidth: 0.55, height: 1.5, colors: [_c(0.38, 0.26, 0.16), _c(0.28, 0.18, 0.10)],
        drops: {'leather': [1, 3], 'raw_beef': [1, 2]}, biomes: [3], day: true, weight: 5));
    s(SpeciesDef(id: 'ghost', name: 'Ghost', hp: 15, damage: 3, speed: 2.4, hostile: true, xp: 14, body: 'humanoid', ghost: true, flying: true,
        halfWidth: 0.3, height: 1.8, colors: [_c(0.80, 0.88, 0.95), _c(0.70, 0.80, 0.92), _c(0.60, 0.70, 0.85)],
        drops: {'magic_dust': [1, 2]}, biomes: [], day: false, weight: 0, effect: 'slow'));
    s(SpeciesDef(id: 'scorpion', name: 'Scorpion', hp: 14, damage: 5, speed: 4.0, hostile: true, xp: 12, body: 'spider',
        halfWidth: 0.5, height: 0.6, colors: [_c(0.65, 0.45, 0.20), _c(0.35, 0.20, 0.10)],
        drops: {'gem_shard': [0, 1], 'string': [0, 2]}, biomes: [4], day: true, weight: 10, effect: 'poison'));
    // Stage 29: the underworld's three creatures (biome 9, spawned any hour) and
    // its boss. The blaze and the Underworld Lord shoot `fire` projectiles that
    // set the target burning; the lord's `volley` is five bolts every four
    // seconds. The heart is not a drop: it comes from the fortress core once the
    // lord is dead.
    s(SpeciesDef(id: 'blaze', name: 'Blaze', hp: 20, damage: 3, speed: 3.6, hostile: true, ranged: true, flying: true, projectile: 'fire', xp: 18, body: 'blob',
        halfWidth: 0.35, height: 0.9, colors: [_c(0.95, 0.65, 0.20)], drops: {'blaze_rod': [0, 2], 'glowstone_dust': [0, 1]},
        biomes: [9], day: true, weight: 16, effect: 'burning'));
    s(SpeciesDef(id: 'dark_skeleton', name: 'Wither Skeleton', hp: 30, damage: 5, speed: 3.0, hostile: true, xp: 22, body: 'humanoid',
        halfWidth: 0.3, height: 2.0, colors: [_c(0.20, 0.18, 0.20), _c(0.15, 0.13, 0.15), _c(0.12, 0.10, 0.12)],
        drops: {'bone': [1, 3], 'coal': [0, 2], 'quartz': [0, 1]}, biomes: [9], day: true, weight: 14, effect: 'wither'));
    s(SpeciesDef(id: 'magma_cube', name: 'Magma Cube', hp: 16, damage: 3, speed: 3.0, hostile: true, hops: true, xp: 12, body: 'blob',
        halfWidth: 0.5, height: 1.0, colors: [_c(0.55, 0.18, 0.10)], drops: {'blaze_rod': [0, 1], 'magic_dust': [0, 1]},
        biomes: [9], day: true, weight: 14, effect: 'burning'));
    s(SpeciesDef(id: 'underworld_lord', name: 'Underworld Lord', hp: 200, damage: 8, speed: 3.2, hostile: true, ranged: true, flying: true, projectile: 'fire', volley: 5,
        xp: 300, body: 'humanoid', boss: true, halfWidth: 0.6, height: 3.2,
        colors: [_c(0.30, 0.08, 0.12), _c(0.55, 0.12, 0.10), _c(0.20, 0.06, 0.08)],
        drops: {'blaze_rod': [8, 8], 'ancient_blade': [1, 1]}, biomes: [], day: true, weight: 0, effect: 'burning'));
    return out;
  }

  static SpeciesDef def(String id) => defs[id]!;

  /// Stage 26: a species' spawn weight in [biome] (`biomeWeight` multiplies the
  /// base per biome).
  static double weightIn(SpeciesDef d, int biome) => d.weight * (d.biomeWeight[biome] ?? 1.0);

  /// Species that may spawn in `biome` at `night` (or in a cave), with weights.
  /// Stage 31: a hostile spawns where it is [dark] (the cell's light,
  /// `Spawner.hostileAllowedAt`), by day or by night, on the surface or in a
  /// cave; the bat's old `maxY` is that same gate now. Weight 0 marks a creature
  /// only a structure places (villager, bosses, the ghost).
  static List<SpeciesDef> candidates(int biome, bool night, bool cave, bool dark, Random rng) {
    final out = <SpeciesDef>[];
    for (final d in defs.values) {
      if (d.weight <= 0) continue;
      if (d.hostile && !dark) continue;
      if (cave) {
        if (d.cave || (d.hostile && !d.day)) out.add(d);
        continue;
      }
      if (!d.biomes.contains(biome)) continue;
      if (d.day && night && d.hostile) continue;
      if (d.day && !d.hostile && night && rng.nextDouble() < 0.7) continue;
      out.add(d);
    }
    return out;
  }
}
