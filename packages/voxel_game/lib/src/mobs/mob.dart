import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../entities/target.dart';
import '../player/character_motor.dart';
import 'behaviors.dart';
import 'goal.dart';
import 'mob_levels.dart';
import 'mob_spec.dart';
import 'rig.dart';

/// A living creature of a [MobSpec]: a body that thinks with its spec's
/// behaviours, moves by its gait, can be hurt, grows with its [level], burns
/// by day when its spec says so, and dies into its loot, its experience and
/// what it splits into.
///
/// Behaviours steer it through [walkTo], [walkDirection], [halt] and
/// [lookAt]; they read [target], [lastHurtBy], [sinceHurt] and [home], and
/// keep their own state in [memory].
class Mob extends GameEntity implements Target {
  /// A [spec] standing at [at].
  Mob(this.spec, Vector3 at) : hp = spec.hp, home = at.clone() {
    halfWidth = spec.halfWidth;
    height = spec.height;
    position = at.clone();
    noclip = false;
    motor = CharacterMotor(
      this,
      MotorTuning(groundAccel: 8.0, airAccel: 4.0, jumpVelocity: spec.gait == Gait.hop ? 7.0 : 8.0),
    );
  }

  /// What it is.
  final MobSpec spec;

  /// Its health.
  double hp;

  /// Its level, from 1: what its health, its strikes and its experience
  /// grow by (`MobSpec.levels`). Set it with [growTo].
  int get level => _level;
  int _level = 1;

  /// Its most health: the spec's, grown by its [level].
  double get maxHp => spec.hp * _scale((l) => l.hp);

  /// What its strikes' damage is multiplied by at its [level].
  double get damageScale => _scale((l) => l.damage);

  /// The experience it is worth at its [level].
  int get xpWorth => (spec.xp * _scale((l) => l.xp)).round();

  double _scale(double Function(MobLevels l) share) {
    final levels = spec.levels;
    return levels == null ? 1.0 : MobLevels.scale(share(levels), _level);
  }

  /// Puts it at [level] (1 or more), whole. Throws for a spec without
  /// `MobSpec.levels`.
  void growTo(int level) {
    if (spec.levels == null) throw StateError('${spec.id} declares no levels');
    if (level < 1) throw ArgumentError.value(level, 'level', 'levels start at 1');
    _level = level;
    hp = maxHp;
  }

  /// Where it wanders around.
  Vector3 home;

  /// What it hunts, set by a behaviour like [Hunt].
  Target? target;

  /// Who hurt it last, or null.
  Target? lastHurtBy;

  /// Where the last hurt came from, or null.
  Vector3? lastHurtFrom;

  /// Seconds since it was last hurt.
  double sinceHurt = double.infinity;

  /// 0..1 how swollen it is (a lit fuse).
  double swell = 0.0;

  /// The on-foot rules, for walkers and hoppers.
  late final CharacterMotor motor;

  /// The model; null headless.
  RigInstance? rig;

  late VoxelGame _game;
  final Map<Behavior, Object> _memory = {};
  final Map<Behavior, double> _cooldowns = {};
  late GoalSelector<Mob, VoxelGame> _brain = GoalSelector(spec.brain);
  bool _dead = false;
  double _deathTime = 0.0;
  double _hurtFlash = 0.0;
  double _burnClock = 0.0;

  /// Whether the day burns it now (`MobSpec.burnsInDaylight`), as last
  /// looked at: twice a second.
  bool burning = false;

  /// Who tamed it, or null for a wild creature.
  Target? get owner => _owner;
  Target? _owner;

  /// Whether it is tamed: it thinks with `MobSpec.tamedBrain`, never burns
  /// and never despawns.
  bool get tamed => _owner != null;

  /// Who rides it, or null. The rider moves it ([carry]); its brain rests.
  Target? rider;

  bool _snap = false;

  /// Tames it for [by]: it forgets its quarrels and thinks with
  /// `MobSpec.tamedBrain` from now on. Throws for one tamed already.
  void tame(Target by) {
    if (tamed) throw StateError('${spec.id} is tamed already');
    _owner = by;
    _brain.stopAll(this, _game);
    _brain = GoalSelector(spec.tamedBrain);
    target = null;
    lastHurtBy = null;
    lastHurtFrom = null;
    halt();
  }

  /// Where its rider's feet go (`MountSpec.seat`).
  Vector3 seat() => position + Vector3(0, spec.mount!.seat, 0);

  /// One step of [dt] under its rider: walks along [wish] at its ridden pace
  /// (`MobSpec.mount`), faster with [sprint], jumping with [jump].
  void carry(double dt, Vector3 wish, {bool sprint = false, bool jump = false}) {
    final mount = spec.mount!;
    motor.step(
      dt,
      wish: wish,
      speed: spec.speed * mount.speed * (sprint ? mount.sprint : 1.0),
      jump: jump || motor.swimming && headInLiquid,
      jumpSpeed: mount.jumpVelocity,
      leaveWater: true,
    );
    if (wish.x * wish.x + wish.z * wish.z > 0.01) _facing = math.atan2(-wish.x, -wish.z);
  }

  /// Puts it at [at] at once, still: a pet carried to its owner. It is drawn
  /// there, not on the way.
  void teleport(Vector3 at) {
    position = at.clone();
    velocity = Vector3.zero();
    halt();
    _snap = true;
  }

  Vector3? _goal;
  Vector3 _direction = Vector3.zero();
  double _speedScale = 1.0;
  Vector3? _look;
  List<Vector3> _path = const [];
  int _pathIndex = 0;
  double _sincePlan = 0.0;
  Vector3? _pathGoal;
  double _hopCooldown = 0.0;
  double _flap = 0.0;

  /// Whether the path planned toward the goal of [walkTo] cannot reach it.
  /// A plan sets it; a goal the last plan was not made for (more than
  /// [replanDistance] from it) clears it until that goal is planned.
  bool pathBlocked = false;

  /// Its number in a networked game (the host's), 0 in a lone one.
  int netId = 0;

  /// A copy of the host's mob on a client: it neither thinks nor moves by
  /// itself, it follows [applyNetState], and a hit on it is sent to the host.
  bool replica = false;

  Vector3? _netTo;

  /// The yaw it faces, radians.
  double get facing => _facing;

  /// A replica's state from the host: where it is, facing where, its health,
  /// and whether it died. Health lost since the last state is a hit, here as
  /// on the host: its number shows over it, and [sinceHurt] starts again.
  void applyNetState(Vector3 at, double yaw, double health, {bool dead = false}) {
    // The first state is where the replica starts, not a hit.
    if (_netTo != null && health < hp) {
      _game.damageNumbers.add(_numberAt(), hp - health);
      sinceHurt = 0.0;
    }
    _netTo = at.clone();
    _facing = yaw;
    hp = health;
    if (dead && !_dead) kill(dropLoot: false);
  }

  @override
  bool get isDead => _dead;

  /// Per-mob state of a shared behaviour: made by [create] on first use.
  T memory<T extends Object>(Behavior behavior, T Function() create) => _memory.putIfAbsent(behavior, create) as T;

  /// True once every [period] seconds of [behavior]'s calls, advancing its
  /// timer by [dt]: an attack's cooldown.
  bool cooldown(Behavior behavior, double dt, double period) {
    final left = (_cooldowns[behavior] ?? 0.0) - dt;
    if (left > 0.0) {
      _cooldowns[behavior] = left;
      return false;
    }
    _cooldowns[behavior] = period;
    return true;
  }

  /// Walks toward [goal] at [speed] of its pace, around walls.
  void walkTo(Vector3 goal, {double speed = 1.0}) {
    final planned = _pathGoal;
    if (planned == null || planned.distanceTo(goal) > replanDistance) pathBlocked = false;
    _goal = goal.clone();
    _speedScale = speed;
  }

  /// Walks along [direction] (horizontal) at [speed] of its pace.
  void walkDirection(Vector3 direction, {double speed = 1.0}) {
    _goal = null;
    _direction = direction.clone();
    _speedScale = speed;
  }

  /// Stands still.
  void halt() {
    _goal = null;
    _direction = Vector3.zero();
  }

  /// Turns the head toward [point] this step.
  void lookAt(Vector3 point) => _look = point.clone();

  String get _defaultHurt => spec.gait == Gait.fly
      ? 'hurt_flying'
      : spec.height < 0.9
      ? 'hurt_small'
      : spec.hp >= 30
      ? 'hurt_large'
      : 'hit';

  /// Its eye, where it looks and shoots from.
  Vector3 eye() => position + Vector3(0, height * 0.85, 0);

  /// Whether nothing that stops a body stands between its eye and [t].
  bool canSee(Target t) {
    final to = t.centre() - eye();
    final d = to.length;
    if (d < 0.001) return true;
    return Reach.toBarrier(_game.world, eye(), to / d, d) >= d;
  }

  @override
  void attached(VoxelGame game) {
    _game = game;
    // Staggered: creatures spawned in one step do not plan in the same steps.
    _sincePlan = game.random.nextDouble() * replanEvery;
    setup(game.world, spec.halfWidth, spec.height);
    if (!game.headless) {
      final r = spec.rig.build(spec.halfWidth, spec.height);
      rig = r;
      node.add(r.root);
      r.place(Vector3.zero());
    }
  }

  @override
  void tick(VoxelGame game, double dt) {
    if (_dead) {
      _deathTime += dt;
      rig?.place(Vector3.zero(), topple: math.min(_deathTime * 4.0, math.pi / 2));
      if (_deathTime > 1.2) removed = true;
      return;
    }
    if (replica) {
      sinceHurt += dt;
      final to = _netTo ?? position;
      final before = position.clone();
      position = position + (to - position) * math.min(1.0, dt * 12.0);
      velocity = (position - before) / math.max(dt, 1e-6);
      _hurtFlash = math.max(_hurtFlash - dt, 0.0);
      _animate(dt);
      syncNode(yaw: rig?.yaw);
      return;
    }
    if (!game.world.isLoaded(IVec3.floor(position))) return;
    sinceHurt += dt;
    _hurtFlash = math.max(_hurtFlash - dt, 0.0);
    if (spec.burnsInDaylight && !tamed) {
      _burn(game, dt);
      if (_dead) return;
    }
    if (rider != null) {
      // Its rider moved it this step (carry); it only shows it.
      _animate(dt);
      syncNode(yaw: rig?.yaw);
      return;
    }
    _look = null;
    _brain.think(this, game);
    if (_brain.holding(BehaviorSlot.move) == null) halt();
    _brain.tick(this, game, dt);
    _locomote(game, dt);
    _animate(dt);
    if (position.y < -10.0) removed = true;
    syncNode(yaw: rig?.yaw, snap: _snap);
    _snap = false;
  }

  /// The behaviours running now.
  Iterable<Behavior> get running => _brain.running.cast<Behavior>();

  void _locomote(VoxelGame game, double dt) {
    final speed = spec.speed * _speedScale;
    var wish = _direction.clone();
    final goal = _goal;
    if (goal != null) wish = spec.gait == Gait.fly ? _flyToward(goal) : _steer(game, goal, dt);
    switch (spec.gait) {
      case Gait.walk:
        motor.step(dt, wish: wish, speed: speed, jump: motor.swimming && headInLiquid, leaveWater: true);
      case Gait.hop:
        _hopCooldown -= dt;
        final wants = wish.length2 > 0.01;
        if (onFloor && wants && _hopCooldown <= 0.0) {
          velocity.y = motor.tuning.jumpVelocity;
          _hopCooldown = target == null ? 0.9 : 0.5;
        }
        applyGravity(dt);
        velocity.x = lerpd(velocity.x, onFloor ? 0.0 : wish.x * speed, math.min(1.0, dt * 3.0));
        velocity.z = lerpd(velocity.z, onFloor ? 0.0 : wish.z * speed, math.min(1.0, dt * 3.0));
        move(dt);
      case Gait.fly:
        _flap -= dt;
        if (goal == null && wish.length2 < 0.01 && _flap <= 0.0) {
          // Idle fliers flutter on a fresh heading every few tenths.
          final r = game.random;
          _flap = 0.2 + r.nextDouble() * 0.4;
          _direction =
              Vector3(r.nextDouble() * 2 - 1, r.nextDouble() * 1.2 - 0.6, r.nextDouble() * 2 - 1).normalized() * 0.4;
          wish = _direction.clone();
        }
        final bob = math.sin(sinceHurt.isFinite ? sinceHurt * 9.0 : _flap * 9.0) * 0.4;
        velocity.x = lerpd(velocity.x, wish.x * speed, math.min(1.0, dt * 6.0));
        velocity.z = lerpd(velocity.z, wish.z * speed, math.min(1.0, dt * 6.0));
        velocity.y = lerpd(velocity.y, wish.y * speed + bob, math.min(1.0, dt * 6.0));
        move(dt);
    }
    final flat = Vector3(wish.x, 0, wish.z);
    if (flat.length2 > 0.01) _facing = math.atan2(-flat.x, -flat.z);
    final look = _look;
    if (look != null && (goal == null || flat.length2 < 0.01)) {
      final to = look - position;
      if (to.x * to.x + to.z * to.z > 0.01) _facing = math.atan2(-to.x, -to.z);
    }
  }

  double _facing = 0.0;

  Vector3 _flyToward(Vector3 goal) {
    final to = goal + Vector3(0, spec.height, 0) - centre();
    return to.length2 > 0.25 ? to.normalized() : Vector3.zero();
  }

  /// Seconds between two plans of a walker on its way.
  static const double replanEvery = 0.6;

  /// The least seconds between two plans, however far the goal moved.
  static const double replanSoonest = 0.2;

  /// A* searches one step runs at most, whichever mobs ask.
  static const int searchesPerStep = 3;

  /// Metres a goal moves before the path planned toward it is for another
  /// goal: it is replanned from [replanSoonest], and its [pathBlocked] cleared.
  static const double replanDistance = 1.5;

  /// A* searches this mob has run.
  int pathsPlanned = 0;

  /// A* toward [goal], re-planned every [replanEvery] s, or sooner (never
  /// before [replanSoonest]) when the goal moved [replanDistance]; the next waypoint is
  /// consumed within 0.35 m. A path walked to its end is not re-planned at
  /// once: an unreachable goal gives a partial or empty one, and planning it
  /// again every step was most of a step's cost with 40 creatures. A plan
  /// that is due when the step has spent its [searchesPerStep] waits for the
  /// next step: mobs that start hunting together, or whose goal (the player)
  /// moved in the same step, would otherwise all search in one.
  Vector3 _steer(VoxelGame game, Vector3 goal, double dt) {
    _sincePlan += dt;
    final moved = _pathGoal == null || _pathGoal!.distanceTo(goal) > replanDistance;
    if ((_sincePlan >= replanEvery || (moved && _sincePlan >= replanSoonest)) && game.searchesLeft > 0) {
      game.searchesLeft--;
      _sincePlan = 0.0;
      pathsPlanned++;
      _pathGoal = goal.clone();
      final from = IVec3.floor(position + Vector3(0, 0.1, 0)), to = IVec3.floor(goal + Vector3(0, 0.1, 0));
      _path = Pathfinder.find(game.world, from, to, costs: game.pathCosts, maxNodes: 400);
      _pathIndex = 0;
      final end = _path.isEmpty ? null : _path.last;
      pathBlocked = end == null || IVec3.floor(end) != to;
    }
    while (_pathIndex < _path.length) {
      final w = _path[_pathIndex];
      final dx = w.x - position.x, dz = w.z - position.z;
      if (dx * dx + dz * dz < 0.35 * 0.35 && (w.y - position.y).abs() < 1.1) {
        _pathIndex++;
        continue;
      }
      final d = math.sqrt(dx * dx + dz * dz);
      return d > 0.001 ? Vector3(dx / d, 0, dz / d) : Vector3.zero();
    }
    // Off the path's end, or no path: straight at the goal.
    final dx = goal.x - position.x, dz = goal.z - position.z;
    final d = math.sqrt(dx * dx + dz * dz);
    return d > 0.3 ? Vector3(dx / d, 0, dz / d) : Vector3.zero();
  }

  void _animate(double dt) {
    final r = rig;
    if (r == null) return;
    final look = _look;
    double? lookYaw;
    if (look != null) {
      final to = look - position;
      var want = math.atan2(-to.x, -to.z) - r.yaw;
      want = (want + math.pi) % (math.pi * 2) - math.pi;
      lookYaw = want;
    }
    r.animate(
      dt,
      speed: math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z),
      targetYaw: _facing,
      onFloor: onFloor,
      flying: spec.gait == Gait.fly,
      lookYaw: lookYaw,
      verticalSpeed: velocity.y,
    );
    r.place(
      Vector3.zero(),
      scale: 1.0 + swell * 0.25,
      shake: _hurtFlash > 0.0 ? math.sin(_hurtFlash * 80.0) * 0.05 : 0.0,
    );
  }

  @override
  double takeDamage(Damage damage) {
    if (_dead) return 0.0;
    if (replica) {
      _hurtFlash = 0.25;
      _game.playSound(spec.hurtSound ?? _defaultHurt, at: centre(), volumeDb: -4.0);
      _game.session?.hitMob(this, damage);
      return 0.0;
    }
    final taken = math.min(hp, damage.amount);
    hp -= damage.amount;
    if (taken > 0.0) _game.damageNumbers.add(_numberAt(), taken);
    sinceHurt = 0.0;
    _hurtFlash = 0.25;
    lastHurtBy = damage.attacker;
    lastHurtFrom = damage.from?.clone();
    _game.playSound(spec.hurtSound ?? _defaultHurt, at: centre(), volumeDb: -4.0);
    final from = damage.from;
    if (from != null && damage.knockback > 0.0) {
      final push = position - from
        ..y = 0.0;
      if (push.length2 > 0) push.normalize();
      final k = damage.knockback * (1.0 - spec.knockbackResistance);
      motor.shove(Vector3(push.x * k, math.max(velocity.y, 4.0 * (1.0 - spec.knockbackResistance)), push.z * k));
    }
    if (hp <= 0.0) kill();
    return taken;
  }

  /// Seconds between two looks at the sky of a creature that burns by day,
  /// and the health each burning look takes.
  static const double burnEvery = 0.5, burnDamage = 0.5;

  /// The daylight rule: twice a second, a creature whose head cell sees the
  /// full sky (light 15) while the [VoxelGame.daylight] is 0.9 or more, out
  /// of liquid, burns for [burnDamage]. A cavern dimension has no sky, so
  /// nothing burns there.
  void _burn(VoxelGame game, double dt) {
    _burnClock -= dt;
    if (_burnClock > 0.0) return;
    _burnClock = burnEvery;
    final head = IVec3.floor(position + Vector3(0, height - 0.15, 0));
    burning = !inLiquid && game.daylight >= 0.9 && game.world.lightAt(head).sky >= 15;
    if (burning) takeDamage(const Damage(burnDamage, source: 'burning', internal: true));
  }

  /// Deals [damage] to [t] and leaves the spec's `onHit` effect on it when
  /// it is the player and the strike took health. Every strike of a
  /// behaviour goes through here.
  double strike(Target t, Damage damage) {
    final taken = t.takeDamage(damage);
    final effect = spec.onHit;
    if (effect != null && taken > 0.0 && identical(t, _game.player)) {
      _game.player.effects.apply(effect.effect, effect.seconds, effect.power);
    }
    return taken;
  }

  /// Where a hit's number starts: over its head.
  Vector3 _numberAt() => position + Vector3(0, height + 0.2, 0);

  /// Dies at once; with [dropLoot], into its loot, the experience it is
  /// worth when the player dealt the last blow, and what it splits into.
  void kill({bool dropLoot = true}) {
    if (_dead) return;
    _dead = true;
    hp = 0.0;
    _brain.reset();
    if (dropLoot) {
      for (final s in spec.loot.roll(_game.random)) {
        _game.dropItem(s.id, s.count, centre());
      }
      if (xpWorth > 0 && identical(lastHurtBy, _game.player)) _game.player.gainXp(xpWorth);
      final split = spec.splitsInto;
      if (split != null) _split(split.mob, split.count);
    }
    _game.mobDied(this);
    if (rig == null) removed = true;
  }

  /// [count] of [id] at its level, tossed out from where it fell.
  void _split(String id, int count) {
    final at = position;
    for (var i = 0; i < count; i++) {
      final a = math.pi * 2 * i / count + _game.random.nextDouble() * 0.5;
      final child = _game.spawnMob(id, at + Vector3(math.cos(a) * 0.4, 0.2, math.sin(a) * 0.4));
      if (child.spec.levels != null) child.growTo(_level);
      child.velocity = Vector3(math.cos(a) * 3.0, 5.0, math.sin(a) * 3.0);
    }
  }
}
