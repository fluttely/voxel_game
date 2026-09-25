/// What a goal needs of the body while it runs. Two goals that share a slot
/// cannot run together: the one with the lower [Goal.priority] number wins it,
/// and a goal that holds none of the other's slots runs beside it (a mob can
/// chase with its legs and bite with its jaws).
enum BehaviorSlot {
  /// Where the creature walks.
  move,

  /// Where the creature looks.
  look,

  /// What the creature strikes.
  attack,
}

/// One thing a creature of type [M] does in a game of type [G], a "goal":
/// it asks to start, runs while it may continue, and competes for
/// [slots] by [priority] (lower wins).
///
/// Engine-neutral: the kit's [Behavior] is a `Goal<Mob, VoxelGame>`, and a
/// game with its own creature class declares its own goals over it and runs
/// them through a [GoalSelector]. Goals are declared once and shared by every
/// creature that uses them, so per-creature state lives on the creature.
abstract class Goal<M, G> {
  /// A goal of [priority] (lower wins a slot).
  const Goal({this.priority = 50});

  /// Lower runs first and takes a shared slot from higher.
  final int priority;

  /// What of the body it needs.
  Set<BehaviorSlot> get slots => const {BehaviorSlot.move};

  /// Whether it wants to start now.
  bool canStart(M mob, G game);

  /// Whether it keeps running; by default while it could start.
  bool canContinue(M mob, G game) => canStart(mob, game);

  /// Called when it starts.
  void start(M mob, G game) {}

  /// Runs one step of [dt] while it holds its slots.
  void tick(M mob, G game, double dt);

  /// Called when it stops (it could not continue, or lost a slot).
  void stop(M mob, G game) {}
}

/// Runs one creature's [goals]: each [think] stops what can no longer continue
/// and starts what may, in list order, a goal taking the slots of running
/// goals it outranks; each [tick] runs what holds its slots.
class GoalSelector<M, G> {
  /// A selector over [goals].
  GoalSelector(this.goals);

  /// The goals it chooses from, in the order they are asked.
  final List<Goal<M, G>> goals;

  final Set<Goal<M, G>> _running = {};

  /// The goals running now, in the order they started.
  Iterable<Goal<M, G>> get running => _running;

  /// The running goal holding [slot], or null.
  Goal<M, G>? holding(BehaviorSlot slot) {
    for (final g in _running) {
      if (g.slots.contains(slot)) return g;
    }
    return null;
  }

  /// Stops what cannot continue, then starts what may.
  void think(M mob, G game) {
    for (final g in _running.toList()) {
      if (!g.canContinue(mob, game)) {
        _running.remove(g);
        g.stop(mob, game);
      }
    }
    for (final g in goals) {
      if (_running.contains(g)) continue;
      // Every slot it needs is free, or held by something it outranks.
      final rivals = [
        for (final r in _running)
          if (r.slots.any(g.slots.contains)) r,
      ];
      if (rivals.any((r) => r.priority <= g.priority)) continue;
      if (!g.canStart(mob, game)) continue;
      for (final r in rivals) {
        _running.remove(r);
        r.stop(mob, game);
      }
      _running.add(g);
      g.start(mob, game);
    }
  }

  /// Runs one step of [dt] of every running goal; a goal stopped by another
  /// during the step does not run.
  void tick(M mob, G game, double dt) {
    for (final g in _running.toList()) {
      if (_running.contains(g)) g.tick(mob, game, dt);
    }
  }

  /// Stops every running goal, calling each one's [Goal.stop].
  void stopAll(M mob, G game) {
    for (final g in _running.toList()) {
      _running.remove(g);
      g.stop(mob, game);
    }
  }

  /// Drops every running goal without a word: the creature is gone (a death) or
  /// thinks with other goals from now on.
  void reset() => _running.clear();
}
