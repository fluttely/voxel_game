import 'music_track.dart';

/// A game's music: [tracks] by name, and the places that play one, by its
/// name. Where the player is picks the track, the first that applies of: the
/// dimension's ([dimensions]), the [cave]'s underground, the biome's
/// ([biomes]), then [day] or [night]. Places that name one track share it, so
/// walking from one to the other does not fade it into itself.
class MusicSpec {
  /// Music over [tracks].
  const MusicSpec({
    required this.tracks,
    this.day,
    this.night,
    this.cave,
    this.biomes = const {},
    this.dimensions = const {},
  });

  /// Every track, by name.
  final Map<String, MusicTrack> tracks;

  /// The track of the day; null for silence where nothing else plays.
  final String? day;

  /// The track of the night; null keeps the [day]'s playing.
  final String? night;

  /// The track underground: well below the ground and out of the sky's light.
  final String? cave;

  /// A biome's own track, by biome name, day and night alike.
  final Map<String, String> biomes;

  /// A dimension's own track, by dimension id (`VoxelGameSpec.dimensionIds`):
  /// it plays everywhere in it, underground too.
  final Map<String, String> dimensions;

  /// The track that plays where the player stands in [dimension], in
  /// [biome], [underground] or not, by day ([night] false) or night; null
  /// for silence.
  String? trackAt({required String dimension, required String biome, required bool underground, required bool night}) {
    final own = dimensions[dimension];
    if (own != null) return own;
    final deep = cave;
    if (underground && deep != null) return deep;
    final local = biomes[biome];
    if (local != null) return local;
    return night ? (this.night ?? day) : day;
  }

  /// Throws [ArgumentError] for a place naming no track of [tracks], a biome
  /// not in [biomeNames] or a dimension not in [dimensionIds].
  void check({required Set<String> biomeNames, required List<String> dimensionIds}) {
    for (final name in [day, night, cave, ...biomes.values, ...dimensions.values]) {
      if (name != null && !tracks.containsKey(name)) throw ArgumentError.value(name, 'music', 'no such track');
    }
    for (final b in biomes.keys) {
      if (!biomeNames.contains(b)) throw ArgumentError.value(b, 'music', 'no such biome');
    }
    for (final d in dimensions.keys) {
      if (!dimensionIds.contains(d)) throw ArgumentError.value(d, 'music', 'no such dimension');
    }
  }
}
