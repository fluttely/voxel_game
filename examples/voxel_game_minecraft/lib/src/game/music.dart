import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'sfx.dart';

/// Background music: the Dawnforge 2D game's biome tracks (Godot
/// `biome_*_data.tres` `music_playlist` / `cave_music_playlist`), streamed from
/// `assets/audio/music/` and looped. The mood is picked by [setContext] (called
/// once a second by `Game`): one per biome group, a night variant that keeps
/// the day's track (the 2D game has no night music), the cave track
/// underground. A change of track crossfades the two handles over [crossfade]
/// seconds with `fadeVolume`.
class Music {
  Music._();
  static final Music instance = Music._();

  static const double crossfade = 3.0;
  static const double gain = 0.45;

  /// The settings' music volume, linear 0..1: scales [gain] only, so the
  /// music is turned down without the world's sounds. The master volume
  /// ([Sfx.setVolume]) still sits over both.
  double volume = 1.0;

  /// Sets [volume] and applies it to the track that is playing now.
  void setVolume(double v) {
    volume = v;
    final h = _active;
    if (h == null || !Sfx.ready) return;
    final soloud = SoLoud.instance;
    if (soloud.getIsValidVoiceHandle(h)) soloud.setVolume(h, gain * volume);
  }

  /// Mood -> track file. Meadow is the 2D forest, Dunes the desert, Frost the
  /// snow, Marsh the swamp, Underworld the lava land, Deep the caves.
  static const Map<String, String> tracks = {
    'Meadow': 'village_market.ogg',
    'Jungle': 'village_market.ogg',
    'Dunes': 'stardust_dreams.ogg',
    'Frost': 'fishing_by_the_lake.ogg',
    'Marsh': 'raindrops_on_the_roof.ogg',
    'Deep': 'rites_of_passage.mp3',
    'Underworld': 'nighttime_fireflies.ogg',
  };

  /// Biome id (`TerrainGenerator.biome*`) -> mood.
  static const Map<int, String> biomeMood = {
    0: 'Meadow', 1: 'Meadow', 2: 'Meadow', 3: 'Meadow', 4: 'Dunes', 5: 'Frost', 6: 'Frost', 7: 'Marsh', 8: 'Jungle',
  };

  /// For the probe: how many tracks actually started on the audio device.
  int handlesPlayed = 0;
  void Function(String track)? onTrackChanged;

  String _mood = '';
  String _track = '';
  final Map<String, AudioSource> _sources = {};
  SoundHandle? _active;
  int _generation = 0;

  String get currentMood => _mood;
  String get currentTrack => _track;

  /// The mood name for where the player stands (pure; unit-tested).
  static String moodFor(int biome, bool night, bool underground, [bool underworld = false]) {
    var name = underworld ? 'Underworld' : (underground ? 'Deep' : (biomeMood[biome] ?? 'Meadow'));
    if (night && !underground && !underworld) name += ' Night';
    return name;
  }

  /// The track file a mood plays (pure; unit-tested).
  static String trackFor(String mood) {
    final base = mood.endsWith(' Night') ? mood.substring(0, mood.length - 6) : mood;
    final t = tracks[base];
    if (t == null) throw ArgumentError('unknown mood $mood');
    return t;
  }

  /// "village_market.ogg" -> "Village Market".
  static String title(String track) => track
      .substring(0, track.lastIndexOf('.'))
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// A change of track starts a crossfade; a mood with the same track (day to
  /// night) keeps playing.
  void setContext(int biome, bool night, bool underground, [bool underworld = false]) {
    _mood = moodFor(biome, night, underground, underworld);
    final track = trackFor(_mood);
    if (track == _track) return;
    _track = track;
    onTrackChanged?.call(title(track));
    final gen = ++_generation;
    unawaited(_crossfadeTo(track, gen));
  }

  Future<void> _crossfadeTo(String track, int gen) async {
    if (!Sfx.ready) return;
    try {
      var source = _sources[track];
      if (source == null) {
        source = await SoLoud.instance.loadAsset('assets/audio/music/$track', mode: LoadMode.disk);
        _sources[track] = source;
      }
      if (gen != _generation) return; // a newer track won while this one loaded
      final soloud = SoLoud.instance;
      final fade = Duration(milliseconds: (crossfade * 1000).toInt());
      final old = _active;
      if (old != null && soloud.getIsValidVoiceHandle(old)) {
        soloud.fadeVolume(old, 0.0, fade);
        soloud.scheduleStop(old, fade + const Duration(milliseconds: 50));
      }
      final h = soloud.play(source, volume: 0.0, looping: true);
      soloud.fadeVolume(h, gain * volume, fade);
      _active = h;
      handlesPlayed++;
    } catch (e) {
      debugPrint('[music] $e');
    }
  }

  /// Whether the active track is a live voice on the audio device (probe).
  bool get isPlaying {
    final h = _active;
    if (h == null || !Sfx.ready) return false;
    try {
      return SoLoud.instance.getIsValidVoiceHandle(h);
    } catch (_) {
      return false;
    }
  }
}
