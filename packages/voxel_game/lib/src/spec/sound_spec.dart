import 'package:sound_recipes/sound_recipes.dart';
import 'package:voxel_engine/content.dart';

import 'music_spec.dart';

/// A game's sound: on or off, extra or replacement sounds, and music by place.
///
/// Blocks sound like their material family (`SoundFamily`): a block tagged
/// `'sound:wood'` sounds of wood; untagged, a liquid sounds of liquid, a block
/// mined with an axe of wood, with a shovel of earth, a see-through solid of
/// glass, a plant or flower of plant, anything else of stone.
///
/// A block's footstep is `step_<family>`, unless it is tagged `'step:<kind>'`:
/// then `step_<kind>`, a sound the game must have (stock — `step_sand`,
/// `step_snow` beside the families' —, one of [recipes] or of [assets]). Recorded
/// takes under a stock name (`step_snow`) replace the synthesised one.
class SoundSpec {
  /// Sound on, the stock set.
  const SoundSpec({
    this.enabled = true,
    this.recipes = const {},
    this.assets = const {},
    this.music,
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

  /// The music, or null for none.
  final MusicSpec? music;

  /// The music's loudness, linear: the default of the player's
  /// `GameSettings.musicVolume`, which the music plays at.
  final double musicVolume;

  /// Whether [name] is a sound the game has: stock, one of [recipes] or of
  /// [assets].
  bool has(String name) => StockSounds.all.containsKey(name) || recipes.containsKey(name) || assets.containsKey(name);

  /// The footstep kind block [t] is tagged with (`'step:sand'` is `sand`), or
  /// null for none. Throws [ArgumentError] for two.
  static String? stepKindOf(BlockType t) {
    String? kind;
    for (final tag in t.tags) {
      if (!tag.startsWith('step:')) continue;
      if (kind != null) throw ArgumentError.value(t.tags, t.id, 'a block steps one way: two step: tags');
      kind = tag.substring(5);
    }
    return kind;
  }
}
