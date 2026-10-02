/// The weather at one place: what the sky does there and what falls.
enum WeatherKind {
  /// A clear sky, nothing falling.
  clear,

  /// Grey, raining.
  rain,

  /// Dark, raining hard, with lightning and thunder.
  storm,

  /// Grey, snowing (a rain or storm over a biome where it snows).
  snow,
}
