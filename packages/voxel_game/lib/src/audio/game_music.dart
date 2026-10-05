import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sound_recipes/sound_recipes.dart';

import '../settings/game_settings.dart';
import '../spec/music_spec.dart';

/// A game's music: the tracks of its [MusicSpec] played by name through a
/// [MusicDirector], at the player's [GameSettings.musicGain], following the
/// settings as they change. `VoxelGameWidget` plays a world's track through
/// one and `TitleScreen` the title's (`TitleSpec.music`).
///
/// It plays on the audio device a `SoundBank` opened, silent where the
/// platform has none, and the device is one: one music is [playing] at a
/// time, from when it is made until it is [close]d, which its owner does
/// before it closes the device.
class GameMusic {
  /// The music of [spec] at [settings]' gain, now [playing]; throws
  /// [StateError] while another is.
  GameMusic(MusicSpec spec, GameSettings settings)
    : _director = MusicDirector(
        {
          for (final e in spec.tracks.entries)
            if (e.value.asset != null) e.key: e.value.asset!,
        },
        recipes: {
          for (final e in spec.tracks.entries)
            if (e.value.score != null) e.key: e.value.score!.toRecipe(),
        },
        gain: settings.musicGain,
      ) {
    if (_playing.value != null) throw StateError('one music at a time: the one playing is not closed');
    _playing.value = this;
  }

  // Keyed by track, not by place: places sharing a track keep it playing.
  final MusicDirector _director;

  /// The music made and not yet closed, or null.
  static ValueListenable<GameMusic?> get playing => _playing;
  static final ValueNotifier<GameMusic?> _playing = ValueNotifier(null);

  /// The track asked for, by name; null for silence.
  String? get track => _director.mood;

  /// The loudness it plays at, linear.
  double get gain => _director.gain;

  /// Fades to [track] (null: silence).
  void play(String? track) => unawaited(_director.setMood(track));

  /// Plays at [settings]' gain from now on, the track playing too.
  void follow(GameSettings settings) => _director.setGain(settings.musicGain);

  /// Silences it and leaves the device to the next.
  void close() {
    assert(identical(_playing.value, this), 'closed twice');
    play(null);
    _playing.value = null;
  }
}
