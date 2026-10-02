import 'weather_spec.dart';

/// Day and night, and the weather.
class SkySpec {
  /// A day of [dayLength] seconds, starting at [startTime] (0 midnight, 0.25
  /// sunrise, 0.5 noon), under [weather] (null: always clear).
  const SkySpec({this.dayLength = 600.0, this.startTime = 0.3, this.cycle = true, this.weather});

  /// Always noon, always clear.
  static const SkySpec alwaysDay = SkySpec(startTime: 0.5, cycle: false);

  /// Seconds from one midnight to the next.
  final double dayLength;

  /// The time of day the game starts at, 0..1.
  final double startTime;

  /// Whether time passes.
  final bool cycle;

  /// Rain, storms and snow, or null for a sky that is always clear.
  final WeatherSpec? weather;
}
