import 'package:sound_recipes/sound_recipes.dart' show MusicScore;

/// One loop of music: a [score] synthesised at first play (no files), an
/// [asset] file, or both, the file playing when the game bundles it and the
/// score when it does not. So a game ships with scores and drops recordings
/// in later, with no change of code.
class MusicTrack {
  /// A track; at least one of [score] and [asset].
  const MusicTrack({this.score, this.asset, this.title})
    : assert(score != null || asset != null, 'a track is a score, a file or both');

  /// The loop written as notes, played while [asset] is not bundled.
  final MusicScore? score;

  /// An audio file the game bundles, by asset path.
  final String? asset;

  /// What the player is told when the track starts (`♪ <title>`); null starts
  /// it unannounced.
  final String? title;
}
