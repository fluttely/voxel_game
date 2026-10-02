/// How often each sky is rolled, as weights against each other: [clear],
/// [rain] and [storm]. What falls from a rain or a storm is the biome's
/// (`Biome.precipitation`): snow where it snows, nothing in a desert.
class WeatherOdds {
  /// Weights, none negative, not all zero. The default is the minecraft
  /// example's: clear a little over half the time, a storm one spell in seven.
  const WeatherOdds({this.clear = 0.55, this.rain = 0.30, this.storm = 0.15})
    : assert(clear >= 0.0 && rain >= 0.0 && storm >= 0.0, 'a weight is not negative'),
      assert(clear + rain + storm > 0.0, 'some sky has a weight');

  /// Always clear: a biome where the weather never turns.
  static const WeatherOdds alwaysClear = WeatherOdds(clear: 1.0, rain: 0.0, storm: 0.0);

  /// The weight of a clear sky.
  final double clear;

  /// The weight of rain.
  final double rain;

  /// The weight of a storm: rain, darker, with lightning and thunder.
  final double storm;
}
