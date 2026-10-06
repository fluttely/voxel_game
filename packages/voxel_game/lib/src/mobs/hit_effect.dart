/// A status effect a creature's strike leaves on the player it lands on: a
/// spider's poison, a stray's slowness.
class HitEffect {
  /// [effect] (an id of `VoxelGameSpec.effects`) for [seconds] at [power].
  const HitEffect(this.effect, {this.seconds = 5.0, this.power = 1.0}) : assert(seconds > 0.0 && power > 0.0);

  /// The effect's id.
  final String effect;

  /// How long it lasts.
  final double seconds;

  /// How strong it is.
  final double power;
}
