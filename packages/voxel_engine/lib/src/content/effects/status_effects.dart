import 'dart:math' as math;

/// How an effect bends one stat, per point of its power.
class StatModifier {
  /// Multiplies the stat by `1 + perPower * power`.
  const StatModifier.multiply(this.perPower) : _kind = 0;

  /// Divides the stat by `1 + perPower * power`.
  const StatModifier.divide(this.perPower) : _kind = 1;

  /// Adds `perPower * power` to the stat.
  const StatModifier.add(this.perPower) : _kind = 2;

  /// The strength per point of power.
  final double perPower;
  final int _kind;
}

/// One timed buff or debuff. With a [period] it ticks: every [period]
/// seconds it deals [damage] and heals [heal], times its power. Its [stats]
/// bend named stats while it lasts.
class EffectType {
  /// An effect.
  const EffectType(this.id, this.name, this.r, this.g, this.b,
      {this.period = 0.0, this.damage = 0.0, this.heal = 0.0, this.bad = false, this.stats = const {}});

  /// The id.
  final String id;

  /// The name a player reads.
  final String name;

  /// Its colour (a HUD chip, a tint), 0..1.
  final double r, g, b;

  /// Seconds between ticks; 0 for an effect that never ticks.
  final double period;

  /// Damage per tick, per point of power.
  final double damage;

  /// Healing per tick, per point of power.
  final double heal;

  /// A debuff: what a cure clears.
  final bool bad;

  /// Stat name to how this effect bends it.
  final Map<String, StatModifier> stats;

  /// Whether it ticks.
  bool get ticks => period > 0.0;
}

/// What one tick of an effect did; the owner decides how it shows.
class EffectEvent {
  /// A tick of [id].
  const EffectEvent(this.id, this.damage, this.heal);

  /// The effect.
  final String id;

  /// Damage dealt.
  final double damage;

  /// Health restored.
  final double heal;
}

/// One active effect: seconds left and power.
class EffectRow {
  /// A row.
  EffectRow(this.time, this.power);

  /// Seconds left.
  double time;

  /// Power.
  double power;

  /// Seconds since its last tick.
  double tick = 0.0;
}

/// The effects on one body. Ticking damage and healing come back from [tick]
/// as events, so the owner applies and shows them.
class StatusEffects {
  /// Effects drawn from [types].
  StatusEffects(this.types);

  /// Every effect there is, by id.
  final Map<String, EffectType> types;

  /// The active effects.
  final Map<String, EffectRow> rows = {};

  /// Effect [id]'s type; throws [ArgumentError] for an unknown one.
  EffectType typeOf(String id) {
    final d = types[id];
    if (d == null) throw ArgumentError.value(id, 'id', 'unknown effect');
    return d;
  }

  /// Starts [id] for [seconds] at [power]; on an active effect keeps the
  /// longer time and the stronger power.
  void apply(String id, double seconds, [double power = 1.0]) {
    typeOf(id);
    final r = rows[id];
    if (r != null) {
      r.time = math.max(r.time, seconds);
      r.power = math.max(r.power, power);
      return;
    }
    rows[id] = EffectRow(seconds, power);
  }

  /// Ends [id].
  void clear(String id) => rows.remove(id);

  /// Ends every bad effect; returns how many.
  int clearBad() {
    final bad = [for (final id in rows.keys) if (typeOf(id).bad) id];
    for (final id in bad) {
      rows.remove(id);
    }
    return bad.length;
  }

  /// Whether [id] is active.
  bool has(String id) => rows.containsKey(id);

  /// [id]'s power, 0 when inactive.
  double power(String id) => rows[id]?.power ?? 0.0;

  /// [id]'s seconds left, 0 when inactive.
  double timeLeft(String id) => rows[id]?.time ?? 0.0;

  /// Advances every row by [dt]; returns the ticks that fired.
  List<EffectEvent> tick(double dt) {
    final events = <EffectEvent>[];
    for (final id in rows.keys.toList()) {
      final r = rows[id]!;
      r.time -= dt;
      if (r.time <= 0.0) {
        rows.remove(id);
        continue;
      }
      final d = typeOf(id);
      if (!d.ticks) continue;
      r.tick += dt;
      if (r.tick >= d.period) {
        r.tick -= d.period;
        events.add(EffectEvent(id, d.damage * r.power, d.heal * r.power));
      }
    }
    return events;
  }

  /// The product of every active effect's multiply and divide modifiers of
  /// [stat]; 1 with none.
  double multiplier(String stat) {
    var m = 1.0;
    for (final e in rows.entries) {
      final mod = types[e.key]!.stats[stat];
      if (mod == null || mod._kind == 2) continue;
      final f = 1.0 + mod.perPower * e.value.power;
      m *= mod._kind == 0 ? f : 1.0 / f;
    }
    return m;
  }

  /// The sum of every active effect's add modifiers of [stat]; 0 with none.
  double bonus(String stat) {
    var sum = 0.0;
    for (final e in rows.entries) {
      final mod = types[e.key]!.stats[stat];
      if (mod != null && mod._kind == 2) sum += mod.perPower * e.value.power;
    }
    return sum;
  }

  /// Each active effect as `[seconds left, power]`.
  Map<String, Object> toJson() => {
        for (final e in rows.entries) e.key: [e.value.time, e.value.power],
      };

  /// Reads [json] back, skipping effects no longer in [types].
  void fromJson(Map<String, Object?> json) {
    rows.clear();
    for (final e in json.entries) {
      if (!types.containsKey(e.key)) continue;
      final pair = [for (final v in e.value! as List<Object?>) (v! as num).toDouble()];
      rows[e.key] = EffectRow(pair[0], pair[1]);
    }
  }
}
