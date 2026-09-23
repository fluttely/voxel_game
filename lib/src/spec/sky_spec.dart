/// Day and night.
class SkySpec {
  /// A day of [dayLength] seconds, starting at [startTime] (0 midnight, 0.25
  /// sunrise, 0.5 noon).
  const SkySpec({this.dayLength = 600.0, this.startTime = 0.3, this.cycle = true});

  /// Always noon.
  static const SkySpec alwaysDay = SkySpec(startTime: 0.5, cycle: false);

  /// Seconds from one midnight to the next.
  final double dayLength;

  /// The time of day the game starts at, 0..1.
  final double startTime;

  /// Whether time passes.
  final bool cycle;
}
