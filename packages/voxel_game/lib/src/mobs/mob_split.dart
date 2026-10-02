/// What a creature becomes when it dies: [count] of mob [mob], at its level,
/// tossed out from where it fell (a slime's two small slimes).
class MobSplit {
  /// [count] of [mob].
  const MobSplit(this.mob, {this.count = 2}) : assert(count > 0);

  /// The id of the mob it splits into.
  final String mob;

  /// How many.
  final int count;
}
