/// Hunger, declared: a bar that empties with time, heals the player while it
/// is full enough and starves them once it is empty. Food fills it.
class HungerSpec {
  /// Hunger; the defaults are a block sandbox's usual pace.
  const HungerSpec({
    this.max = 20.0,
    this.secondsPerPoint = 45.0,
    this.regenAbove = 6.0,
    this.regenSeconds = 3.0,
    this.regenAmount = 1.0,
    this.starveSeconds = 4.0,
    this.starveDamage = 1.0,
  }) : assert(max > 0.0 && secondsPerPoint > 0.0 && regenSeconds > 0.0 && starveSeconds > 0.0);

  /// A full bar.
  final double max;

  /// Seconds for the bar to lose one point.
  final double secondsPerPoint;

  /// The player heals while the bar holds at least this much.
  final double regenAbove;

  /// Seconds between two heals.
  final double regenSeconds;

  /// Health one heal gives back.
  final double regenAmount;

  /// Seconds between two pangs once the bar is empty.
  final double starveSeconds;

  /// Damage of one pang.
  final double starveDamage;
}
