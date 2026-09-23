import 'dart:math' as math;

import 'package:sound_recipes/sound_recipes.dart';

/// Procedural sound effects: short WAV bursts synthesised at startup (no asset
/// files), played through SoLoud. VK6: sound_recipes' [SoundBank] with its
/// stock set — the sounds this file used to synthesise, name for name — plus
/// this game's recorded footsteps.
class Sfx {
  Sfx._();

  /// The 2D game's ground kinds, each a folder of four footstep takes.
  static const List<String> stepKinds = ['forest', 'desert', 'snow', 'swamp', 'lava'];

  static const double _tau = math.pi * 2;

  /// The four sounds only this game has, beside the stock set.
  static final Map<String, SoundRecipe> _own = {
    'break': SoundRecipe(0.18, (t, p, r) => (r.nextDouble() * 2.0 - 1.0) * math.pow(1.0 - p, 2.0) * 0.8 + math.sin(t * 220.0 * _tau) * (1.0 - p) * 0.2),
    'place': SoundRecipe(0.10, (t, p, r) => math.sin(t * 180.0 * _tau) * math.pow(1.0 - p, 3.0) * 0.6),
    'bolt': SoundRecipe(0.3, (t, p, r) => (math.sin(t * 200.0 * _tau) * math.sin(t * 37.0 * _tau) + (r.nextDouble() - 0.5) * 0.3) * (1.0 - p) * 0.5),
    'quest': SoundRecipe(0.5, (t, p, r) => math.sin(t * (p < 0.5 ? 523.0 : 784.0) * _tau) * (1.0 - p) * 0.4),
  };

  static final SoundBank _bank = SoundBank(recipes: {...StockSounds.all, ..._own}, assets: {
    for (final kind in stepKinds) 'footstep_$kind': [for (var i = 1; i <= 4; i++) 'assets/audio/footstep/$kind/${kind}_$i.wav'],
  });

  /// Stage 24: the settings' master volume (Godot's bus 0), linear 0..1.
  static double _volume = 1.0;

  static bool get muted => _bank.muted;
  static set muted(bool value) => _bank.muted = value;

  static void setVolume(double v) {
    _volume = v;
    _bank.setVolume(v);
  }

  static Future<void> init() async {
    if (await _bank.init()) _bank.setVolume(_volume);
  }

  static bool get ready => _bank.ready;

  /// One footstep of [kind] (`stepKinds`), a random take of the four.
  static void playStep(String kind, [double volumeDb = 0.0, double pitch = 1.0]) =>
      _bank.play('footstep_$kind', volumeDb: volumeDb, pitch: pitch);

  static void play(String name, [double volumeDb = 0.0, double pitch = 1.0]) => _bank.play(name, volumeDb: volumeDb, pitch: pitch);
}
