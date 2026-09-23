import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'stock_sounds.dart';
import 'wav.dart';

/// Something that plays named sounds. The kit talks to this, so a game can
/// run silent (tests, servers) or swap the engine.
abstract interface class SoundPlayer {
  /// Plays [name] at [volumeDb] (0 full, -6 half), at [pitch] times its speed
  /// (with a little random variation so repeats do not drone).
  void play(String name, {double volumeDb = 0.0, double pitch = 1.0});
}

/// Plays nothing and remembers what it was asked to play: for tests.
class SilentSounds implements SoundPlayer {
  /// Every name asked for, in order.
  final List<String> played = [];

  @override
  void play(String name, {double volumeDb = 0.0, double pitch = 1.0}) => played.add(name);
}

/// Named sounds through SoLoud: each [recipes] entry rendered to WAV bytes at
/// [init] (no files), plus [assets] (a name to one or more takes, a random one
/// played each time).
class SoundBank implements SoundPlayer {
  /// A bank of [recipes] (the stock set when omitted) and [assets].
  SoundBank({Map<String, SoundRecipe>? recipes, this.assets = const {}}) : recipes = recipes ?? StockSounds.all;

  /// Synthesised sounds by name.
  final Map<String, SoundRecipe> recipes;

  /// Recorded sounds by name: asset paths, one take picked per play.
  final Map<String, List<String>> assets;

  final Map<String, List<AudioSource>> _sources = {};
  final math.Random _rng = math.Random();
  bool _ready = false;

  /// Nothing plays while set.
  bool muted = false;

  /// Whether the audio device is open and the sounds loaded.
  bool get ready => _ready;

  /// Opens the audio device and loads every sound; false when the platform
  /// has no audio (the bank then stays silent).
  Future<bool> init() async {
    if (_ready) return true;
    try {
      await SoLoud.instance.init();
      for (final e in recipes.entries) {
        _sources[e.key] = [await SoLoud.instance.loadMem('${e.key}.wav', renderWav(e.value))];
      }
      for (final e in assets.entries) {
        _sources[e.key] = [for (final path in e.value) await SoLoud.instance.loadAsset(path)];
      }
      _ready = true;
    } catch (e) {
      debugPrint('[sound_recipes] audio unavailable: $e');
    }
    return _ready;
  }

  /// Whether [name] is in the bank.
  bool has(String name) => _sources.containsKey(name) || recipes.containsKey(name) || assets.containsKey(name);

  /// The master volume, linear 0..1.
  void setVolume(double volume) {
    if (_ready) SoLoud.instance.setGlobalVolume(volume);
  }

  @override
  void play(String name, {double volumeDb = 0.0, double pitch = 1.0}) {
    if (!_ready || muted) return;
    final takes = _sources[name];
    if (takes == null || takes.isEmpty) return;
    final volume = math.pow(10.0, volumeDb / 20.0).toDouble().clamp(0.0, 1.0);
    try {
      final handle = SoLoud.instance.play(takes[_rng.nextInt(takes.length)], volume: volume, paused: true);
      SoLoud.instance.setRelativePlaySpeed(handle, pitch * (0.92 + _rng.nextDouble() * 0.16));
      SoLoud.instance.setPause(handle, false);
    } catch (e) {
      debugPrint('[sound_recipes] $e');
    }
  }

  /// Closes the audio device.
  void dispose() {
    if (_ready) SoLoud.instance.deinit();
    _ready = false;
  }
}

/// Background music chosen by mood: [tracks] maps a mood to an asset path; a
/// change of mood crossfades the two over [crossfade] seconds. Needs an
/// initialised [SoundBank] (the audio device).
class MusicDirector {
  /// A director over [tracks] at [gain].
  MusicDirector(this.tracks, {this.gain = 0.45, this.crossfade = 3.0});

  /// Mood to asset path.
  final Map<String, String> tracks;

  /// The music's loudness, linear.
  double gain;

  /// Seconds a change of track fades over.
  final double crossfade;

  final Map<String, AudioSource> _loaded = {};
  SoundHandle? _active;
  String? _mood;
  int _generation = 0;

  /// The mood playing, or null.
  String? get mood => _mood;

  /// Plays the track of [mood] (null: silence), fading the old one out.
  Future<void> setMood(String? mood) async {
    if (mood == _mood) return;
    _mood = mood;
    final gen = ++_generation;
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) return;
    final fade = Duration(milliseconds: (crossfade * 1000).toInt());
    final old = _active;
    if (old != null && soloud.getIsValidVoiceHandle(old)) {
      soloud.fadeVolume(old, 0.0, fade);
      soloud.scheduleStop(old, fade + const Duration(milliseconds: 50));
    }
    _active = null;
    final path = mood == null ? null : tracks[mood];
    if (path == null) return;
    try {
      final source = _loaded[path] ??= await soloud.loadAsset(path, mode: LoadMode.disk);
      if (gen != _generation) return; // a newer mood won while this one loaded
      final h = soloud.play(source, volume: 0.0, looping: true);
      soloud.fadeVolume(h, gain, fade);
      _active = h;
    } catch (e) {
      debugPrint('[sound_recipes] music: $e');
    }
  }
}
