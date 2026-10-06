import 'package:vector_math/vector_math.dart';

import '../mobs/hit_effect.dart';

/// What hurt a [Target]: the amount, where it came from, and who.
class Damage {
  /// [amount] of damage of [source] (`'melee'`, `'fall'`, `'lava'`, a
  /// projectile's kind), from [from] with [knockback] metres a second of
  /// shove, dealt by [attacker] when someone dealt it. [internal] for a hurt
  /// from within the body, [crit] for a critical blow, [effect] for one that
  /// leaves a status effect on a player it hurts.
  const Damage(
    this.amount, {
    this.source = 'melee',
    this.from,
    this.knockback = 0.0,
    this.attacker,
    this.internal = false,
    this.crit = false,
    this.effect,
  });

  /// How much health it takes.
  final double amount;

  /// What kind of hurt.
  final String source;

  /// Where it came from, for the shove; null for no direction.
  final Vector3? from;

  /// The shove's speed.
  final double knockback;

  /// Who dealt it, or null.
  final Target? attacker;

  /// A hurt from within (a status effect's tick, hunger): armour does not
  /// turn it aside and the moment of grace after a blow does not stop it.
  final bool internal;

  /// A critical blow (`PlayerSpec.critChance`): [amount] already counts it,
  /// and its number over a creature is marked.
  final bool crit;

  /// The status effect it leaves on a player it hurts (a creature's
  /// `MobSpec.onHit`, a shot's `ProjectileSpec.onHit`): worn when the hurt
  /// lands past the filters and armour, on whichever side the player is. A
  /// creature wears none.
  final HitEffect? effect;

  /// This hurt, leaving [effect].
  Damage withEffect(HitEffect? effect) => Damage(
    amount,
    source: source,
    from: from,
    knockback: knockback,
    attacker: attacker,
    internal: internal,
    crit: crit,
    effect: effect,
  );
}

/// Anything that can be hunted and hurt: the player, a mob, a remote player.
abstract interface class Target {
  /// Its feet.
  Vector3 get position;

  /// The middle of its body: what is aimed at.
  Vector3 centre();

  /// Whether it is dead (and out of the fight).
  bool get isDead;

  /// Takes [damage]; returns how much health it lost.
  double takeDamage(Damage damage);
}
