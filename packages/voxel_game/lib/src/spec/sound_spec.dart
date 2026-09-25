import 'package:sound_recipes/sound_recipes.dart';

/// A game's sound: on or off, extra or replacement sounds, and music by mood.
///
/// Blocks sound like their material family (`SoundFamily`): a block tagged
/// `'sound:wood'` sounds of wood; untagged, a liquid sounds of liquid, a block
/// mined with an axe of wood, with a shovel of earth, a see-through solid of
/// glass, a plant or flower of plant, anything else of stone.
class SoundSpec {
  /// Sound on, the stock set.
  const SoundSpec({
    this.enabled = true,
    this.recipes = const {},
    this.assets = const {},
    this.music = const {},
    this.musicVolume = 0.45,
  });

  /// No sound at all.
  static const SoundSpec off = SoundSpec(enabled: false);

  /// Whether the game makes sound.
  final bool enabled;

  /// Synthesised sounds added to (or replacing) the stock set, by name.
  final Map<String, SoundRecipe> recipes;

  /// Recorded sounds by name: asset paths, a random take each time.
  final Map<String, List<String>> assets;

  /// Music by mood: `'day'`, `'night'`, `'cave'`, or a biome name, to an asset
  /// path. The mood is the biome's when it has a track, else day or night;
  /// underground it is cave.
  final Map<String, String> music;

  /// The music's loudness, linear.
  final double musicVolume;
}
