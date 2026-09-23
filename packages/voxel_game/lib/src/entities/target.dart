import 'package:vector_math/vector_math.dart';

/// What hurt a [Target]: the amount, where it came from, and who.
class Damage {
  /// [amount] of damage of [source] (`'melee'`, `'fall'`, `'lava'`, a
  /// projectile's kind), from [from] with [knockback] metres a second of
  /// shove, dealt by [attacker] when someone dealt it.
  const Damage(this.amount, {this.source = 'melee', this.from, this.knockback = 0.0, this.attacker});

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
