import 'package:voxel_engine/content.dart';

import 'behaviors.dart';
import 'hit_effect.dart';
import 'mob_levels.dart';
import 'mob_split.dart';
import 'mount_spec.dart';
import 'rig.dart';
import 'spawn_place.dart';

/// How a creature gets about.
enum Gait {
  /// Walks, following A* paths around walls; jumps steps; swims.
  walk,

  /// Hops like a slime: leaps toward where it goes.
  hop,

  /// Flies: no gravity, steers in three dimensions.
  fly,
}

/// Where and when a mob appears by itself.
class SpawnRule {
  /// A rule: [weight] against the other candidates, in [biomes] (any when
  /// null), the weight multiplied in a biome of [biomeWeights], where the
  /// light is between [minLight] and [maxLight] (block light plus sky light
  /// scaled by the day, 0..15), on the [place] it allows, in groups of
  /// [group].
  const SpawnRule({
    this.weight = 10,
    this.biomes,
    this.biomeWeights = const {},
    this.minLight = 0,
    this.maxLight = 15,
    this.group = (1, 1),
    this.place = SpawnPlace.surface,
    this.maxAlive = 8,
  });

  /// The creatures of the night: only in the dark (light 7 or less), on the
  /// surface and in caves.
  const SpawnRule.dark({
    int weight = 10,
    List<String>? biomes,
    Map<String, double> biomeWeights = const {},
    (int, int) group = (1, 1),
    int maxAlive = 12,
  }) : this(
         weight: weight,
         biomes: biomes,
         biomeWeights: biomeWeights,
         maxLight: 7,
         group: group,
         place: SpawnPlace.anywhere,
         maxAlive: maxAlive,
       );

  /// The animals of the day: only in daylight (light 9 or more).
  const SpawnRule.daylight({
    int weight = 10,
    List<String>? biomes,
    Map<String, double> biomeWeights = const {},
    (int, int) group = (2, 4),
    int maxAlive = 10,
  }) : this(weight: weight, biomes: biomes, biomeWeights: biomeWeights, minLight: 9, group: group, maxAlive: maxAlive);

  /// The creatures of the caves: only in a pocket of air underground, at any
  /// light (a bat, a cave slime).
  const SpawnRule.cave({int weight = 10, List<String>? biomes, (int, int) group = (1, 1), int maxAlive = 8})
    : this(weight: weight, biomes: biomes, group: group, place: SpawnPlace.cave, maxAlive: maxAlive);

  /// How likely against the other candidates of a spot.
  final int weight;

  /// The biome names it appears in, or null for any.
  final List<String>? biomes;

  /// A multiplier on [weight] by biome name (a swamp night crawls with
  /// spiders); 1 in a biome not named.
  final Map<String, double> biomeWeights;

  /// The dimmest light it appears in.
  final int minLight;

  /// The brightest light it appears in.
  final int maxLight;

  /// How many appear together, fewest and most.
  final (int, int) group;

  /// On the surface, in caves, or either.
  final SpawnPlace place;

  /// It stops appearing while this many of it are alive.
  final int maxAlive;

  /// Its weight in [biome].
  double weightIn(String biome) => weight * (biomeWeights[biome] ?? 1.0);
}

/// A creature, declared: how it looks ([rig]), how big it is, how it moves
/// ([gait]) and thinks ([brain]), what it drops ([loot]) and is worth
/// ([xp]), how it grows with the player ([levels]), what it does to what it
/// strikes ([onHit]) and becomes when it dies ([splitsInto]), how it is
/// tamed ([tameWith]) and then thinks ([tamedBrain]) and carries a rider
/// ([mount]), whether it stays ([persistent]) or walks through walls
/// ([ghost]), and where it spawns.
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
    this.loot = const LootTable([]),
    this.xp = 0,
    this.levels,
    this.burnsInDaylight = false,
    this.splitsInto,
    this.onHit,
    this.tameWith = const [],
    this.tameChance = 1.0,
    this.tamedBrain = const [],
    this.mount,
    this.persistent = false,
    this.ghost = false,
    this.spawn,
    this.knockbackResistance = 0.0,
    this.hurtSound,
    this.boss = false,
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

  /// What it drops when it dies, rolled once.
  final LootTable loot;

  /// The experience the player gains for killing it (`PlayerSpec.xp` must
  /// be declared when any creature is worth some).
  final int xp;

  /// How it grows with the player, or null to stay as declared.
  final MobLevels? levels;

  /// Whether it burns under the open noon sky, out of liquid: a point of
  /// health a second while its head sees full sky light and the daylight is
  /// 0.9 or more.
  final bool burnsInDaylight;

  /// What it becomes when it dies, or null.
  final MobSplit? splitsInto;

  /// The status effect its strike leaves on the player, or null.
  final HitEffect? onHit;

  /// The items that tame it, used on it one at a time; empty for a creature
  /// that is never tamed by hand.
  final List<String> tameWith;

  /// The chance, 0..1, that one of [tameWith] tames it.
  final double tameChance;

  /// What it does once tamed, replacing [brain]: a companion's
  /// `[MeleeAttack(...), PetFight(), Heel()]`, a mount's `[MountWait()]`.
  final List<Behavior> tamedBrain;

  /// How it carries a rider once tamed (its owner rides it by using it), or
  /// null for a creature that is never ridden.
  final MountSpec? mount;

  /// Whether it stays where it is however far the player goes: the spawner
  /// never takes it away, and the save keeps it (a tamed creature is kept
  /// either way).
  final bool persistent;

  /// Whether it passes through blocks: a flier ([gait] must be [Gait.fly])
  /// that no wall stops.
  final bool ghost;

  /// Where it appears by itself; null for never (placed by the game).
  final SpawnRule? spawn;

  /// 0 takes a full shove, 1 none.
  final double knockbackResistance;

  /// The sound it makes when hurt; by default by its build (a small one
  /// squeaks, a big one groans, a flier chirps).
  final String? hurtSound;

  /// Whether it is a boss: while one lives in the loaded world, the default
  /// HUD shows the nearest one's health in a bar at the top of the screen.
  final bool boss;
}
