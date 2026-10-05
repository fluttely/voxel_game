import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import '../entities/projectile.dart';
import '../entities/target.dart';
import 'goal.dart';
import 'mob.dart';

/// One thing a mob does, a "goal": it asks to start, runs while it
/// may continue, and competes for [slots] by [priority] (lower wins). A mob's
/// brain is a list of them; add your own by subclassing, or inline with
/// [Behavior.custom]. It is a [Goal] over the kit's [Mob], chosen by a
/// [GoalSelector].
///
/// Behaviours are declared once and shared by every mob of a spec, so they
/// hold no state: per-mob state lives in [Mob.memory].
abstract class Behavior extends Goal<Mob, VoxelGame> {
  /// A behaviour of [priority] (lower wins a slot).
  const Behavior({super.priority = 50});

  /// A behaviour from closures: [canStart] asks, [tick] runs it.
  const factory Behavior.custom({
    required int priority,
    required bool Function(Mob mob, VoxelGame game) canStart,
    required void Function(Mob mob, VoxelGame game, double dt) tick,
    Set<BehaviorSlot> slots,
  }) = _CustomBehavior;
}

class _CustomBehavior extends Behavior {
  const _CustomBehavior({
    required super.priority,
    required this._canStart,
    required this._tick,
    this._slots = const {BehaviorSlot.move},
  });

  final bool Function(Mob mob, VoxelGame game) _canStart;
  final void Function(Mob mob, VoxelGame game, double dt) _tick;
  final Set<BehaviorSlot> _slots;

  @override
  Set<BehaviorSlot> get slots => _slots;

  @override
  bool canStart(Mob mob, VoxelGame game) => _canStart(mob, game);

  @override
  void tick(Mob mob, VoxelGame game, double dt) => _tick(mob, game, dt);
}

class _WanderState {
  Vector3? goal;
  double wait = 0.0;
}

/// Strolls about its home at [speed] of its pace, pausing between walks.
class Wander extends Behavior {
  /// Walks to a spot within [radius] of home, waits 1.5-4 s, and again.
  const Wander({super.priority = 90, this.radius = 10.0, this.speed = 0.5});

  /// How far from home it strays.
  final double radius;

  /// Its pace, as a share of the mob's speed.
  final double speed;

  /// This behaviour with the given fields replaced.
  Wander copyWith({int? priority, double? radius, double? speed}) =>
      Wander(priority: priority ?? this.priority, radius: radius ?? this.radius, speed: speed ?? this.speed);

  @override
  bool canStart(Mob mob, VoxelGame game) => true;

  @override
  void tick(Mob mob, VoxelGame game, double dt) {
    final s = mob.memory(this, _WanderState.new);
    final goal = s.goal;
    if (goal == null) {
      mob.halt();
      s.wait -= dt;
      if (s.wait > 0) return;
      final a = game.random.nextDouble() * math.pi * 2, r = game.random.nextDouble() * radius;
      s.goal = mob.home + Vector3(math.cos(a) * r, 0, math.sin(a) * r);
      return;
    }
    mob.walkTo(goal, speed: speed);
    final dx = goal.x - mob.position.x, dz = goal.z - mob.position.z;
    if (dx * dx + dz * dz < 0.6 || mob.pathBlocked) {
      s.goal = null;
      s.wait = 1.5 + game.random.nextDouble() * 2.5;
    }
  }

  @override
  void stop(Mob mob, VoxelGame game) => mob.memory(this, _WanderState.new).goal = null;
}

/// Hunts the nearest target within [range] and chases it, losing it past
/// [giveUpRange]. With [whenProvoked] it only hunts whoever hurt it (a
/// neutral animal). It sets [Mob.target], which the attacks read.
class Hunt extends Behavior {
  /// A hunter.
  const Hunt({
    super.priority = 20,
    this.range = 16.0,
    this.giveUpRange = 32.0,
    this.whenProvoked = false,
    this.prey = const [],
  });

  /// How far it notices a target.
  final double range;

  /// How far it chases before giving up.
  final double giveUpRange;

  /// Only whoever hurt it in the last 30 seconds.
  final bool whenProvoked;

  /// Mob ids it hunts besides the player (a wolf hunts sheep).
  final List<String> prey;

  /// This behaviour with the given fields replaced.
  Hunt copyWith({int? priority, double? range, double? giveUpRange, bool? whenProvoked, List<String>? prey}) => Hunt(
    priority: priority ?? this.priority,
    range: range ?? this.range,
    giveUpRange: giveUpRange ?? this.giveUpRange,
    whenProvoked: whenProvoked ?? this.whenProvoked,
    prey: prey ?? this.prey,
  );

  @override
  bool canStart(Mob mob, VoxelGame game) {
    Target? best;
    if (whenProvoked) {
      final by = mob.lastHurtBy;
      if (by != null && !by.isDead && mob.sinceHurt < 30.0 && _dist(mob, by) < range) best = by;
    } else {
      var bestD = range;
      for (final t in game.targetsOf(prey)) {
        if (t == mob || t.isDead) continue;
        final d = _dist(mob, t);
        if (d < bestD) {
          bestD = d;
          best = t;
        }
      }
    }
    if (best == null) return false;
    mob.target = best;
    return true;
  }

  @override
  bool canContinue(Mob mob, VoxelGame game) {
    final t = mob.target;
    return t != null && !t.isDead && _dist(mob, t) < giveUpRange;
  }

  @override
  void tick(Mob mob, VoxelGame game, double dt) {
    final t = mob.target;
    if (t != null) mob.walkTo(t.position);
  }

  /// Forgets the target only when it is lost: a behaviour that takes the
  /// legs for a moment (a fuse, a flight) still needs to know who it was.
  @override
  void stop(Mob mob, VoxelGame game) {
    final t = mob.target;
    if (t == null || t.isDead || _dist(mob, t) >= giveUpRange) mob.target = null;
  }

  static double _dist(Mob mob, Target t) => mob.position.distanceTo(t.position);
}

/// Strikes its [Mob.target] for [damage] (grown by the mob's level) when it
/// is within [reach] and in sight, once per [cooldown]; the strike leaves the
/// spec's `onHit` effect on the player.
class MeleeAttack extends Behavior {
  /// A bite, a punch, a kick.
  const MeleeAttack({
    super.priority = 10,
    required this.damage,
    this.reach = 1.6,
    this.cooldown = 1.2,
    this.knockback = 5.0,
  });

  /// Health a strike takes.
  final double damage;

  /// How far it reaches beyond its own half width.
  final double reach;

  /// Seconds between strikes.
  final double cooldown;

  /// The shove a strike gives.
  final double knockback;

  /// This behaviour with the given fields replaced.
  MeleeAttack copyWith({int? priority, double? damage, double? reach, double? cooldown, double? knockback}) =>
      MeleeAttack(
        priority: priority ?? this.priority,
        damage: damage ?? this.damage,
        reach: reach ?? this.reach,
        cooldown: cooldown ?? this.cooldown,
        knockback: knockback ?? this.knockback,
      );

  @override
  Set<BehaviorSlot> get slots => const {BehaviorSlot.attack, BehaviorSlot.look};

  @override
  bool canStart(Mob mob, VoxelGame game) {
    final t = mob.target;
    return t != null &&
        !t.isDead &&
        mob.centre().distanceTo(t.centre()) <= reach + mob.halfWidth + 0.5 &&
        mob.canSee(t);
  }

  @override
  void tick(Mob mob, VoxelGame game, double dt) {
    final t = mob.target!;
    mob.lookAt(t.centre());
    if (mob.cooldown(this, dt, cooldown)) {
      mob.rig?.swing();
      mob.strike(t, Damage(damage * mob.damageScale, from: mob.position, knockback: knockback, attacker: mob));
    }
  }
}

/// Keeps [keepAway]..[holdRange] from its [Mob.target] and shoots it with
/// [projectile] every [cooldown] seconds within [range].
class RangedAttack extends Behavior {
  /// An archer, a mage.
  const RangedAttack({
    super.priority = 15,
    required this.projectile,
    this.range = 16.0,
    this.keepAway = 6.0,
    this.holdRange = 12.0,
    this.cooldown = 2.0,
  });

  /// What it shoots.
  final ProjectileSpec projectile;

  /// How far it shoots.
  final double range;

  /// Closer than this it backs off.
  final double keepAway;

  /// Farther than this it closes in.
  final double holdRange;

  /// Seconds between shots.
  final double cooldown;

  /// This behaviour with the given fields replaced.
  RangedAttack copyWith({
    int? priority,
    ProjectileSpec? projectile,
    double? range,
    double? keepAway,
    double? holdRange,
    double? cooldown,
  }) => RangedAttack(
    priority: priority ?? this.priority,
    projectile: projectile ?? this.projectile,
    range: range ?? this.range,
    keepAway: keepAway ?? this.keepAway,
    holdRange: holdRange ?? this.holdRange,
    cooldown: cooldown ?? this.cooldown,
  );

  @override
  Set<BehaviorSlot> get slots => const {BehaviorSlot.move, BehaviorSlot.attack, BehaviorSlot.look};

  @override
  bool canStart(Mob mob, VoxelGame game) {
    final t = mob.target;
    return t != null && !t.isDead && mob.position.distanceTo(t.position) <= range && mob.canSee(t);
  }

  @override
  void tick(Mob mob, VoxelGame game, double dt) {
    final t = mob.target!;
    final d = mob.position.distanceTo(t.position);
    if (d < keepAway) {
      final away = mob.position - t.position
        ..y = 0;
      mob.walkDirection(away.length2 > 0 ? away.normalized() : Vector3(1, 0, 0));
    } else if (d > holdRange) {
      mob.walkTo(t.position);
    } else {
      mob.halt();
    }
    mob.lookAt(t.centre());
    if (mob.cooldown(this, dt, cooldown)) {
      mob.rig?.swing();
      final from = mob.eye();
      game.shoot(projectile, from: from, at: t.centre(), owner: mob, power: mob.damageScale);
    }
  }
}

class _FleeState {
  double left = 0.0;
  Vector3 from = Vector3.zero();
}

/// Runs from whatever hurt it for [seconds], at [speed] of its pace.
class FleeWhenHurt extends Behavior {
  /// A frightened animal.
  const FleeWhenHurt({super.priority = 5, this.seconds = 4.0, this.speed = 1.4});

  /// How long it runs.
  final double seconds;

  /// Its pace, as a share of the mob's speed.
  final double speed;

  /// This behaviour with the given fields replaced.
  FleeWhenHurt copyWith({int? priority, double? seconds, double? speed}) =>
      FleeWhenHurt(priority: priority ?? this.priority, seconds: seconds ?? this.seconds, speed: speed ?? this.speed);

  @override
  bool canStart(Mob mob, VoxelGame game) => mob.sinceHurt < 0.2 && mob.lastHurtFrom != null;

  @override
  bool canContinue(Mob mob, VoxelGame game) => mob.memory(this, _FleeState.new).left > 0.0;

  @override
  void start(Mob mob, VoxelGame game) {
    mob.memory(this, _FleeState.new)
      ..left = seconds
      ..from = mob.lastHurtFrom!.clone();
  }

  @override
  void tick(Mob mob, VoxelGame game, double dt) {
    final s = mob.memory(this, _FleeState.new);
    s.left -= dt;
    if (mob.sinceHurt < 0.2 && mob.lastHurtFrom != null) {
      s
        ..left = seconds
        ..from = mob.lastHurtFrom!.clone();
    }
    final away = mob.position - s.from
      ..y = 0;
    mob.walkDirection(away.length2 > 0.0001 ? away.normalized() : Vector3(1, 0, 0), speed: speed);
  }
}

class _FuseState {
  double fuse = 0.0;
}

/// Hisses when its target is within [trigger] and blows up after [fuse]
/// seconds, dealing up to [damage] within [radius] and breaking blocks when
/// [breaksBlocks]. Out of reach, the fuse goes out.
class Explode extends Behavior {
  /// A creeper.
  const Explode({
    super.priority = 8,
    this.trigger = 2.5,
    this.fuse = 1.5,
    this.radius = 3.0,
    this.damage = 12.0,
    this.breaksBlocks = true,
  });

  /// How near the target lights the fuse.
  final double trigger;

  /// Seconds from lit to bang.
  final double fuse;

  /// The blast's reach.
  final double radius;

  /// Damage at the centre, falling off to 0 at [radius].
  final double damage;

  /// Whether the blast breaks blocks.
  final bool breaksBlocks;

  /// This behaviour with the given fields replaced.
  Explode copyWith({
    int? priority,
    double? trigger,
    double? fuse,
    double? radius,
    double? damage,
    bool? breaksBlocks,
  }) => Explode(
    priority: priority ?? this.priority,
    trigger: trigger ?? this.trigger,
    fuse: fuse ?? this.fuse,
    radius: radius ?? this.radius,
    damage: damage ?? this.damage,
    breaksBlocks: breaksBlocks ?? this.breaksBlocks,
  );

  @override
  Set<BehaviorSlot> get slots => const {BehaviorSlot.move, BehaviorSlot.attack};

  @override
  bool canStart(Mob mob, VoxelGame game) {
    final t = mob.target;
    return t != null && !t.isDead && mob.position.distanceTo(t.position) < trigger;
  }

  @override
  bool canContinue(Mob mob, VoxelGame game) {
    final t = mob.target;
    return t != null && !t.isDead && mob.position.distanceTo(t.position) < trigger * 2.0;
  }

  @override
  void tick(Mob mob, VoxelGame game, double dt) {
    final s = mob.memory(this, _FuseState.new);
    mob.halt();
    s.fuse += dt;
    mob.swell = s.fuse / fuse;
    if (s.fuse >= fuse) {
      game.explode(
        mob.centre(),
        radius: radius,
        damage: damage * mob.damageScale,
        breaksBlocks: breaksBlocks,
        source: mob,
      );
      mob.kill(dropLoot: false);
    }
  }

  @override
  void stop(Mob mob, VoxelGame game) {
    mob.memory(this, _FuseState.new).fuse = 0.0;
    mob.swell = 0.0;
  }
}

/// Turns its head toward the player within [range].
class LookAtPlayer extends Behavior {
  /// A curious animal.
  const LookAtPlayer({super.priority = 80, this.range = 6.0});

  /// How near the player must be.
  final double range;

  /// This behaviour with the given fields replaced.
  LookAtPlayer copyWith({int? priority, double? range}) =>
      LookAtPlayer(priority: priority ?? this.priority, range: range ?? this.range);

  @override
  Set<BehaviorSlot> get slots => const {BehaviorSlot.look};

  @override
  bool canStart(Mob mob, VoxelGame game) =>
      !game.player.isDead && mob.position.distanceTo(game.player.position) < range;

  @override
  void tick(Mob mob, VoxelGame game, double dt) => mob.lookAt(game.player.centre());
}

/// A companion fights what its owner fights: the nearest wild creature
/// within [range] that hunts the owner or that the owner hurt in the last
/// ten seconds, chased until it dies or gets [giveUpRange] away. It sets
/// [Mob.target], which the attacks read: a pet's brain strikes with a
/// [MeleeAttack] beside it.
class PetFight extends Behavior {
  /// A companion's fight.
  const PetFight({super.priority = 20, this.range = 12.0, this.giveUpRange = 24.0});

  /// How far from it a foe is noticed.
  final double range;

  /// How far it chases before giving up.
  final double giveUpRange;

  /// This behaviour with the given fields replaced.
  PetFight copyWith({int? priority, double? range, double? giveUpRange}) => PetFight(
    priority: priority ?? this.priority,
    range: range ?? this.range,
    giveUpRange: giveUpRange ?? this.giveUpRange,
  );

  @override
  bool canStart(Mob mob, VoxelGame game) {
    final owner = mob.owner;
    if (owner == null) return false;
    Mob? best;
    var bestD = range;
    for (final m in game.mobs) {
      if (m == mob || m.isDead || m.tamed) continue;
      final foe = identical(m.target, owner) || identical(m.lastHurtBy, owner) && m.sinceHurt < 10.0;
      if (!foe) continue;
      final d = m.position.distanceTo(mob.position);
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    if (best == null) return false;
    mob.target = best;
    return true;
  }

  @override
  bool canContinue(Mob mob, VoxelGame game) {
    final t = mob.target;
    return t != null && !t.isDead && mob.position.distanceTo(t.position) < giveUpRange;
  }

  @override
  void tick(Mob mob, VoxelGame game, double dt) => mob.walkTo(mob.target!.position);

  @override
  void stop(Mob mob, VoxelGame game) => mob.target = null;
}

class _HeelState {
  bool walking = false;
}

/// A companion heels: it walks after its owner once they are [follow]
/// away, stops within [stay], and is carried beside them past [teleport]
/// (the first of the four sides of their feet where it stands clear, or
/// their own spot).
class Heel extends Behavior {
  /// A companion's heel.
  const Heel({super.priority = 90, this.follow = 4.0, this.stay = 2.0, this.teleport = 30.0, this.speed = 1.0});

  /// How far the owner goes before it follows.
  final double follow;

  /// How near it stops.
  final double stay;

  /// How far the owner goes before it is carried to them.
  final double teleport;

  /// Its pace, as a share of the mob's speed.
  final double speed;

  /// This behaviour with the given fields replaced.
  Heel copyWith({int? priority, double? follow, double? stay, double? teleport, double? speed}) => Heel(
    priority: priority ?? this.priority,
    follow: follow ?? this.follow,
    stay: stay ?? this.stay,
    teleport: teleport ?? this.teleport,
    speed: speed ?? this.speed,
  );

  @override
  bool canStart(Mob mob, VoxelGame game) {
    final owner = mob.owner;
    return owner != null && !owner.isDead;
  }

  @override
  void tick(Mob mob, VoxelGame game, double dt) {
    final owner = mob.owner!;
    final s = mob.memory(this, _HeelState.new);
    final d = mob.position.distanceTo(owner.position);
    if (d > teleport) {
      mob.teleport(_besideOf(game, owner.position));
      s.walking = false;
      return;
    }
    if (d > follow) s.walking = true;
    if (d < stay) s.walking = false;
    if (s.walking) {
      mob.walkTo(owner.position, speed: speed);
    } else {
      mob.halt();
    }
  }

  static Vector3 _besideOf(VoxelGame game, Vector3 feet) {
    final w = game.world;
    for (final side in const [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]) {
      final cell = IVec3.floor(feet + Vector3(0, 0.1, 0)) + side;
      if (!w.isSolid(cell) && !w.isSolid(cell + IVec3.up) && w.isSolid(cell + IVec3.down)) {
        return Vector3(cell.x + 0.5, cell.y.toDouble(), cell.z + 0.5);
      }
    }
    return feet.clone();
  }
}

/// A tamed mount waits for its owner: it trots after them while they are
/// [follow]..[leash] away and stands otherwise; it never fights.
class MountWait extends Behavior {
  /// A mount's wait.
  const MountWait({super.priority = 90, this.follow = 4.0, this.stay = 2.5, this.leash = 20.0});

  /// How far the owner goes before it trots after them.
  final double follow;

  /// How near it stops.
  final double stay;

  /// How far the owner goes before it stays where it is.
  final double leash;

  /// This behaviour with the given fields replaced.
  MountWait copyWith({int? priority, double? follow, double? stay, double? leash}) => MountWait(
    priority: priority ?? this.priority,
    follow: follow ?? this.follow,
    stay: stay ?? this.stay,
    leash: leash ?? this.leash,
  );

  @override
  bool canStart(Mob mob, VoxelGame game) => mob.owner != null;

  @override
  void tick(Mob mob, VoxelGame game, double dt) {
    final owner = mob.owner!;
    final d = mob.position.distanceTo(owner.position);
    if (d > leash || d < stay || owner.isDead) {
      mob.halt();
    } else if (d > follow) {
      mob.walkTo(owner.position);
    }
  }
}
