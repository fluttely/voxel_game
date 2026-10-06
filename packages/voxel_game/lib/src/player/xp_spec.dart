import 'dart:math' as math;

/// Experience, declared: how many points each level takes, and what a level
/// is worth.
class XpSpec {
  /// Levels from level 0 that take `base * (level + 1) ^ exponent` points
  /// each, and raise the most health by [hpPerLevel].
  const XpSpec({this.base = 40.0, this.exponent = 1.45, this.hpPerLevel = 0.0})
    : assert(base >= 1.0 && exponent >= 0.0 && hpPerLevel >= 0.0);

  /// The points level 0 takes to leave.
  final double base;

  /// How much steeper each level is than the last.
  final double exponent;

  /// Most health each level adds.
  final double hpPerLevel;

  /// The points it takes to go from [level] to the next.
  int toNext(int level) => (base * math.pow(level + 1, exponent)).floor();
}
