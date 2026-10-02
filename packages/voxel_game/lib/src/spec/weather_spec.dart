import 'weather_odds.dart';

/// The weather: a sky rolled every few minutes ([odds], or a biome's own in
/// [biomes], at the player), eased in over [fadeSeconds]. Rain and storms
/// grey the sky and pull the fog in, a storm darker and with lightning
/// ([thunder]); what falls is the player's biome's (`Biome.precipitation`):
/// rain, snow, or nothing.
///
/// Only a game that decides rolls (a lone game, a host); a client's sky is
/// the host's, sent as it turns, its bolts struck on the client's own clock.
class WeatherSpec {
  /// Weather rolled anew every [minSpell] to [maxSpell] seconds.
  const WeatherSpec({
    this.odds = const WeatherOdds(),
    this.biomes = const {},
    this.minSpell = 90.0,
    this.maxSpell = 240.0,
    this.fadeSeconds = 4.0,
    this.thunder = 'thunder',
    this.minBolt = 4.0,
    this.maxBolt = 14.0,
  }) : assert(minSpell > 0.0 && minSpell <= maxSpell, 'a spell lasts minSpell..maxSpell seconds'),
       assert(fadeSeconds > 0.0, 'the weather takes some time to turn'),
       assert(minBolt > 0.0 && minBolt <= maxBolt, 'a bolt follows the last after minBolt..maxBolt seconds');

  /// The odds of each sky where the player's biome has none in [biomes].
  final WeatherOdds odds;

  /// A biome's own odds, by its name (`Biome.name`): a land where it rains
  /// more, or never. Every name must be one of the world's biomes.
  final Map<String, WeatherOdds> biomes;

  /// The shortest spell, in seconds, before the sky is rolled again.
  final double minSpell;

  /// The longest spell.
  final double maxSpell;

  /// Seconds the weather takes to come in fully, or to clear.
  final double fadeSeconds;

  /// The sound a bolt makes (a stock or `SoundSpec` sound).
  final String thunder;

  /// The fewest seconds from one bolt of a storm to the next.
  final double minBolt;

  /// The most.
  final double maxBolt;
}
