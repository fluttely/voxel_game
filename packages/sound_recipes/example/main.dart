// Sounds with no audio files: the stock set and one of your own, synthesised
// to WAV at start-up and played through flutter_soloud.
//
// Copy this file into a Flutter app's lib/main.dart and `flutter run`.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sound_recipes/sound_recipes.dart';

/// A sound of your own: a rising two-tone chime, half a second long. `t` is
/// the time in seconds, `p` goes 0 to 1 through the sound, `rng` is for noise.
final SoundRecipe chime = SoundRecipe(0.5, (t, p, rng) {
  final pitch = p < 0.5 ? 660.0 : 880.0;
  return math.sin(t * pitch * math.pi * 2) * (1.0 - p) * 0.4;
});

/// The stock sounds plus the chime.
final SoundBank bank = SoundBank(recipes: {...StockSounds.all, 'chime': chime});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opens the audio device and renders every recipe. False: no audio here,
  // and the bank stays silent instead of failing.
  final ok = await bank.init();
  runApp(MaterialApp(home: SoundBoard(audio: ok)));
}

/// One button a sound.
class SoundBoard extends StatelessWidget {
  /// A board; [audio] says whether the device opened.
  const SoundBoard({super.key, required this.audio});

  /// Whether sounds can be heard.
  final bool audio;

  static const List<String> _names = [
    'chime',
    'hit',
    'pickup',
    'levelup',
    'explode',
    'door',
    'break_${SoundFamily.stone}',
    'step_${SoundFamily.earth}',
    'place_${SoundFamily.wood}',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(audio ? 'sound_recipes' : 'sound_recipes (no audio device)')),
        body: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in _names)
              // volumeDb: 0 is full, -6 is about half; pitch 1 is as made.
              FilledButton(onPressed: () => bank.play(name, volumeDb: -3), child: Text(name)),
          ],
        ),
      );
}
