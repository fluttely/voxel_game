/// How a crop grows: after [seconds] lit by at least [minLight] (sky or
/// block light, 0..15) it becomes the block [into], its next stage. The last
/// stage has no growth.
class Growth {
  /// A stage that becomes [into] after [seconds] of light.
  const Growth(this.into, {required this.seconds, this.minLight = 9})
    : assert(seconds > 0.0),
      assert(minLight >= 0 && minLight <= 15);

  /// The next stage, a block id.
  final String into;

  /// Seconds of light it takes.
  final double seconds;

  /// The least light it grows in; in less it waits.
  final int minLight;
}
