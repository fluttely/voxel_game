part of 'mob.dart';

/// VK5.5: a Dawnforge creature thinks with goals on the kit's [GoalSelector],
/// the way a kit `MobSpec` declares its `brain`. Each goal is what used to be
/// one state of the mob's state machine; the one holding the legs
/// ([BehaviorSlot.move]) names the [MobState] the rest of the game reads.
///
/// Goals are const and shared by every creature; what they remember lives on
/// the [Mob] (its timer, its roam phase, its fuse), read here as the same
/// library.
abstract class MobGoal extends Goal<Mob, Game> {
  const MobGoal({required super.priority});

  /// The state it shows while it holds the legs.
  MobState label(Mob mob);
}

/// A species' brain: its row in the table, read as a list of goals. A tamed
/// creature thinks with its owner's goals instead.
List<MobGoal> brainOf(SpeciesDef sp, {required bool tamed}) {
  if (tamed) return sp.mount ? const [MountWait()] : const [PetFight(), Heel()];
  if (sp.trader) return const [Roam()];
  return [
    if (!sp.hostile) const Flee(),
    if (sp.hostile || sp.neutral) ...[
      if (sp.ranged)
        const Kite()
      else ...[
        if (sp.explodes) const Fuse() else const Strike(),
        const Chase(),
      ],
    ],
    const Roam(),
  ];
}

/// Stands a while, then walks a while on a random heading; a creature with a
/// home (a villager) turns back to it past [Mob.homeRadius].
class Roam extends MobGoal {
  const Roam() : super(priority: 90);

  @override
  MobState label(Mob mob) => mob._wandering ? MobState.wander : MobState.idle;

  @override
  bool canStart(Mob mob, Game game) => true;

  @override
  void start(Mob mob, Game game) => mob._wandering = false;

  @override
  void tick(Mob mob, Game game, double dt) {
    final rng = game.random;
    if (!mob._wandering) {
      mob._dir = Vector3.zero();
      if (mob._timer <= 0.0) {
        mob._wandering = true;
        mob._timer = 1.5 + rng.nextDouble() * 2.5;
        final a = rng.nextDouble() * math.pi * 2;
        mob._dir = Vector3(math.cos(a), 0, math.sin(a));
      }
      return;
    }
    if (mob._timer <= 0.0) {
      mob._wandering = false;
      mob._timer = 1.0 + rng.nextDouble() * 4.0;
    }
    final h = mob.home;
    if (h != null) {
      final away = mob.position - h;
      away.y = 0.0;
      // Stage 26: a villager turns back to its village.
      if (away.length > Mob.homeRadius) mob._dir = mob._steer(-away, h);
    }
  }
}

/// Goes after its target along an A* path: a hostile creature within its aggro
/// range, or anything its attacker provoked. It gives the chase up past 2.2
/// times that range, and calms down.
class Chase extends MobGoal {
  const Chase() : super(priority: 20);

  @override
  MobState label(Mob mob) => MobState.chase;

  @override
  bool canStart(Mob mob, Game game) => mob._provoked || mob._sees;

  @override
  bool canContinue(Mob mob, Game game) => !mob._lost;

  @override
  void tick(Mob mob, Game game, double dt) => mob._dir = mob._steer(mob._toTarget, mob._target!.position);

  /// Calms down only when the target is lost: a strike that takes the legs
  /// for a moment keeps it angry.
  @override
  void stop(Mob mob, Game game) {
    if (mob._lost) mob._angry = false;
  }
}

/// A ranged creature's chase: it backs off inside 6 m, holds inside 13 m and
/// shoots within 16 m every 2.2 s, an arrow from a humanoid and frost from
/// anything else.
class Kite extends Chase {
  const Kite();

  @override
  Set<BehaviorSlot> get slots => const {BehaviorSlot.move, BehaviorSlot.attack};

  @override
  void tick(Mob mob, Game game, double dt) {
    super.tick(mob, game, dt);
    final dist = mob._dist;
    if (dist < 6.0) {
      mob._dir = -mob._dir;
    } else if (dist < 13.0) {
      mob._dir = Vector3.zero();
    }
    if (dist < 16.0 && mob._attackCd <= 0.0) {
      mob._attackCd = 2.2;
      mob._face(mob._toTarget);
      final target = mob._target!;
      game.spawnProjectile(mob.centre() + Vector3(0, 0.3, 0), (target.centre() - mob.centre()).normalized() * 24.0,
          mob.species.damage, mob, mob.species.body == 'humanoid' ? 'arrow' : 'frost');
    }
  }
}

/// Stands and swings at a target within reach with nothing in between, every
/// 1.3 s, passing on the species' or the affix's effect.
class Strike extends MobGoal {
  const Strike() : super(priority: 10);

  @override
  Set<BehaviorSlot> get slots => const {BehaviorSlot.move, BehaviorSlot.attack};

  @override
  MobState label(Mob mob) => MobState.attack;

  @override
  bool canStart(Mob mob, Game game) => mob._engaged && mob._dist < mob._reach && mob.canReach(mob._target!);

  @override
  bool canContinue(Mob mob, Game game) => mob._dist <= mob._reach + 0.4 && mob.canReach(mob._target!);

  @override
  void tick(Mob mob, Game game, double dt) {
    mob._dir = Vector3.zero();
    mob._face(mob._toTarget);
    if (mob._attackCd <= 0.0) {
      mob._attackCd = 1.3;
      mob._anim.startSwing();
      mob.hurtTarget(mob._target!, mob.damageDealt());
      Sfx.play('hit', -4.0);
    }
  }
}

/// A boomer's attack: in reach it stops, swells and blows up about 1.1 s
/// later. Once lit it never goes out.
class Fuse extends Strike {
  const Fuse();

  @override
  bool canContinue(Mob mob, Game game) => true;

  @override
  void tick(Mob mob, Game game, double dt) {
    mob._dir = Vector3.zero();
    mob._face(mob._toTarget);
    mob._fuse += 0.016;
    mob._modelScale = 1.0 + mob._fuse * 0.5;
    if (mob._fuse > 1.1) {
      game.explode(mob.centre(), 3.0, 9.0 + mob.mobLevel, mob);
      mob.removed = true;
    }
  }
}

/// A frightened animal runs from the nearest target while the flight timer
/// set by the hit lasts.
class Flee extends MobGoal {
  const Flee() : super(priority: 5);

  @override
  MobState label(Mob mob) => MobState.flee;

  @override
  bool canStart(Mob mob, Game game) => mob._frightened;

  @override
  bool canContinue(Mob mob, Game game) => mob._timer > 0.0;

  @override
  void tick(Mob mob, Game game, double dt) {
    if (mob._dist < 12.0 && mob._toTarget.length2 > 0) mob._dir = -mob._toTarget.normalized();
  }
}

/// A tamed mount never fights: it trots after its owner while they are near
/// (4 to 20 m) and waits otherwise.
class MountWait extends MobGoal {
  const MountWait() : super(priority: 90);

  @override
  MobState label(Mob mob) => MobState.idle;

  @override
  bool canStart(Mob mob, Game game) => true;

  @override
  void tick(Mob mob, Game game, double dt) {
    final dist = mob._dist;
    if (dist > 20.0 || dist < 2.5) {
      mob._dir = Vector3.zero();
    } else if (dist > 4.0) {
      mob._dir = mob._toTarget.normalized();
    }
  }
}

/// A companion fights what the player fights: the nearest hostile creature
/// chasing within 12 m, bitten every second for the species' damage plus 2.
class PetFight extends MobGoal {
  const PetFight() : super(priority: 20);

  @override
  Set<BehaviorSlot> get slots => const {BehaviorSlot.move, BehaviorSlot.attack};

  @override
  MobState label(Mob mob) => MobState.idle;

  @override
  bool canStart(Mob mob, Game game) {
    final pt = mob._petTarget;
    if (pt != null && (pt.removed || pt.state == MobState.dead)) mob._petTarget = null;
    if (mob._petTarget == null) {
      var best = 12.0;
      for (final other in game.mobs) {
        if (other.species.hostile && other.state == MobState.chase) {
          final d = (other.position - mob.position).length;
          if (d < best) {
            best = d;
            mob._petTarget = other;
          }
        }
      }
    }
    return mob._petTarget != null;
  }

  @override
  void tick(Mob mob, Game game, double dt) {
    final target = mob._petTarget!;
    final toT = target.position - mob.position;
    toT.y = 0.0;
    if (toT.length < 1.6 + mob.halfWidth) {
      mob._dir = Vector3.zero();
      mob._face(toT);
      if (mob._attackCd <= 0.0) {
        mob._attackCd = 1.0;
        target.takeDamage(mob.species.damage + 2, mob.position, 4.0, mob);
        game.spawnDamageNumber(target.centre(), mob.species.damage + 2, Vector3(0.6, 0.8, 1.0));
      }
    } else {
      mob._dir = toT.normalized();
    }
  }
}

/// A companion heels: it follows its owner past 4 m, stops inside 2 m, and
/// is carried to them past 30 m.
class Heel extends MobGoal {
  const Heel() : super(priority: 90);

  @override
  MobState label(Mob mob) => MobState.idle;

  @override
  bool canStart(Mob mob, Game game) => true;

  @override
  void tick(Mob mob, Game game, double dt) {
    final dist = mob._dist;
    if (dist > 4.0) {
      mob._dir = mob._toTarget.normalized();
    } else if (dist < 2.0) {
      mob._dir = Vector3.zero();
    }
    if (dist > 30.0) mob.position = mob.player.position + Vector3(1, 0.5, 1);
  }
}
