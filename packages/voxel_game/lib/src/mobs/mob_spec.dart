import 'behaviors.dart';
import 'rig.dart';

/// How a creature gets about.
enum Gait {
  /// Walks, following A* paths around walls; jumps steps; swims.
  walk,

  /// Hops like a slime: leaps toward where it goes.
  hop,

  /// Flies: no gravity, steers in three dimensions.
  fly,
}

/// What a mob drops when it dies.
class Drop {
  /// [min]..[max] of [item], with [chance] 0..1 to drop at all.
  const Drop(this.item, this.min, this.max, {this.chance = 1.0});

  /// The item.
  final String item;

  /// The fewest.
  final int min;

  /// The most.
  final int max;

  /// The chance to drop at all.
  final double chance;
}

/// Where and when a mob appears by itself.
class SpawnRule {
  /// A rule: [weight] against the other candidates, in [biomes] (any when
  /// null), where the light is between [minLight] and [maxLight] (block light
  /// plus sky light scaled by the day, 0..15), in groups of [group].
  const SpawnRule({
    this.weight = 10,
    this.biomes,
    this.minLight = 0,
    this.maxLight = 15,
    this.group = (1, 1),
    this.onSurfaceOnly = true,
    this.maxAlive = 8,
  });

  /// The creatures of the night: only in the dark (light 7 or less).
  const SpawnRule.dark({int weight = 10, List<String>? biomes, (int, int) group = (1, 1), int maxAlive = 12})
    : this(weight: weight, biomes: biomes, maxLight: 7, group: group, maxAlive: maxAlive);

  /// The animals of the day: only in daylight (light 9 or more).
  const SpawnRule.daylight({int weight = 10, List<String>? biomes, (int, int) group = (2, 4), int maxAlive = 10})
    : this(weight: weight, biomes: biomes, minLight: 9, group: group, maxAlive: maxAlive);

  /// How likely against the other candidates of a spot.
  final int weight;

  /// The biome names it appears in, or null for any.
  final List<String>? biomes;

  /// The dimmest light it appears in.
  final int minLight;

  /// The brightest light it appears in.
  final int maxLight;

  /// How many appear together, fewest and most.
  final (int, int) group;

  /// Only on the ground under open sky (not in caves).
  final bool onSurfaceOnly;

  /// It stops appearing while this many of it are alive.
  final int maxAlive;
}

/// A creature, declared: how it looks ([rig]), how big it is, how it moves
/// ([gait]) and thinks ([brain]), what it drops and where it spawns.
///
/// ```dart
/// MobSpec('zombie', hp: 20, speed: 3.2,
///     rig: Rig.humanoid(skin: 0x4C8A4C, armsForward: true, redEyes: true),
///     brain: [MeleeAttack(damage: 3), Hunt(range: 16), Wander()],
///     spawn: SpawnRule.dark());
/// ```
class MobSpec {
  /// A creature named [id].
  const MobSpec(
    this.id, {
    this._name,
    this.hp = 10,
    this.speed = 2.5,
    this.halfWidth = 0.3,
    this.height = 1.75,
    this.rig = const Rig.humanoid(),
    this.gait = Gait.walk,
    this.brain = const [Wander()],
    this.drops = const [],
    this.spawn,
    this.knockbackResistance = 0.0,
    this.hurtSound,
  });

  /// The id.
  final String id;

  final String? _name;

  /// The name a player reads; the id in title case by default.
  String get name => _name ?? id.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  /// Health.
  final double hp;

  /// Walking speed, metres a second.
  final double speed;

  /// Half the collider's width.
  final double halfWidth;

  /// The collider's height.
  final double height;

  /// How it looks.
  final Rig rig;

  /// How it moves.
  final Gait gait;

  /// What it does, as behaviours; see [Behavior] for how they share the body.
  final List<Behavior> brain;

  /// What it drops.
  final List<Drop> drops;

  /// Where it appears by itself; null for never (placed by the game).
  final SpawnRule? spawn;

  /// 0 takes a full shove, 1 none.
  final double knockbackResistance;

  /// The sound it makes when hurt; by default by its build (a small one
  /// squeaks, a big one groans, a flier chirps).
  final String? hurtSound;
}
