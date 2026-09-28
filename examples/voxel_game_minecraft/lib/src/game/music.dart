import 'dart:async';

import 'package:sound_recipes/sound_recipes.dart';

import 'sfx.dart';

/// Background music, one track per biome group, looped. The mood is picked by
/// [setContext] (called once a second by `Game`): one per biome group, a night
/// variant that keeps the day's track, the cave track underground. Playback is
/// sound_recipes' [MusicDirector], which crossfades a change of track.
///
/// Every track is `assets/audio/music/<track>.mp3` (`meadow.mp3`,
/// `dunes.mp3`, ...). The repository ships none of them: a track whose file is
/// not there plays its [StockMusic] score instead, synthesised at first use.
/// Drop a file with the track's name into that folder and it plays in its
/// place, with no code change.
class Music {
  Music._();
  static final Music instance = Music._();

  static const double crossfade = 3.0;
  static const double gain = 0.45;

  /// Where a track's own file goes.
  static String assetFor(String track) => 'assets/audio/music/$track.mp3';

  /// Track -> the stock score played while its file is absent.
  static const Map<String, MusicScore> scores = {
    'meadow': StockMusic.pastoral,
    'dunes': StockMusic.arid,
    'frost': StockMusic.frozen,
    'marsh': StockMusic.murky,
    'deep': StockMusic.cavern,
    'underworld': StockMusic.infernal,
  };

  /// Mood -> track. Meadow is the forest, Dunes the desert, Frost the snow,
  /// Marsh the swamp, Underworld the lava land, Deep the caves; the jungle
  /// shares the meadow's.
  static const Map<String, String> tracks = {
    'Meadow': 'meadow',
    'Jungle': 'meadow',
    'Dunes': 'dunes',
    'Frost': 'frost',
    'Marsh': 'marsh',
    'Deep': 'deep',
    'Underworld': 'underworld',
  };

  /// Biome id (`TerrainGenerator.biome*`) -> mood.
  static const Map<int, String> biomeMood = {
    0: 'Meadow', 1: 'Meadow', 2: 'Meadow', 3: 'Meadow', 4: 'Dunes', 5: 'Frost', 6: 'Frost', 7: 'Marsh', 8: 'Jungle',
  };

  final MusicDirector _director = MusicDirector(
    {for (final t in scores.keys) t: assetFor(t)},
    recipes: {for (final e in scores.entries) e.key: e.value.toRecipe()},
    gain: gain,
    crossfade: crossfade,
  );

  /// The settings' music volume, linear 0..1: scales [gain] only, so the
  /// music is turned down without the world's sounds. The master volume
  /// ([Sfx.setVolume]) still sits over both.
  double volume = 1.0;

  /// Sets [volume] and applies it to the track that is playing now.
  void setVolume(double v) {
    volume = v;
    _director.setGain(gain * volume);
  }

  /// For the probe: how many tracks actually started on the audio device.
  int handlesPlayed = 0;
  void Function(String track)? onTrackChanged;

  String _mood = '';
  String _track = '';

  String get currentMood => _mood;
  String get currentTrack => _track;

  /// Whether the track playing is its own file or the synthesised score;
  /// null before it starts.
  MusicOrigin? get origin => _director.origin;

  /// The mood name for where the player stands (pure; unit-tested).
  static String moodFor(int biome, bool night, bool underground, [bool underworld = false]) {
    var name = underworld ? 'Underworld' : (underground ? 'Deep' : (biomeMood[biome] ?? 'Meadow'));
    if (night && !underground && !underworld) name += ' Night';
    return name;
  }

  /// The track a mood plays (pure; unit-tested).
  static String trackFor(String mood) {
    final base = mood.endsWith(' Night') ? mood.substring(0, mood.length - 6) : mood;
    final t = tracks[base];
    if (t == null) throw ArgumentError('unknown mood $mood');
    return t;
  }

  /// "meadow" -> "Meadow".
  static String title(String track) => track[0].toUpperCase() + track.substring(1);

  /// A change of track starts a crossfade; a mood with the same track (day to
  /// night) keeps playing.
  void setContext(int biome, bool night, bool underground, [bool underworld = false]) {
    _mood = moodFor(biome, night, underground, underworld);
    final track = trackFor(_mood);
    if (track == _track) return;
    _track = track;
    onTrackChanged?.call(title(track));
    if (!Sfx.ready) return;
    unawaited(_director.setMood(track).then((_) {
      if (_director.mood == track && _director.isPlaying) handlesPlayed++;
    }));
  }

  /// Whether the active track is a live voice on the audio device (probe).
  bool get isPlaying => Sfx.ready && _director.isPlaying;
}
