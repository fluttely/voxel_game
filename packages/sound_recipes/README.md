# sound_recipes

Game audio with no audio files: a sound is a recipe — a length and a function
of time — rendered to WAV when the game starts and played through
`flutter_soloud`. Comes with a stock set of sounds for every material, and
music that crossfades by mood.

Nothing here is specific to voxels, or to any genre: it is one file of
synthesis, a bank and a player.

> **Status: 0.1.0**, the first release. The API can still change.

## Features

- `SoundRecipe` + `renderWav`: a sound is a length and a waveform function.
- `StockSounds`: `break_`, `place_` and `step_` for every `SoundFamily`, plus `hit`, `hurt`, `pickup`, `explode` and more.
- `SoundBank`: plays sounds by name, from recipes or asset files.
- `SoundPlayer` / `SilentSounds`: play through an interface, so tests and servers stay silent.
- `MusicDirector`: one track per mood, crossfaded.

## Install

```yaml
dependencies:
  sound_recipes: ^0.1.0
```

Dart SDK `^3.13.0`.
Needs Flutter (it plays through `flutter_soloud`).

## Usage

1. **Make a bank** of the stock sounds, plus your own if you like.

   ```dart
   final bank = SoundBank(recipes: {
     ...StockSounds.all,
     'chime': SoundRecipe(0.5, (t, p, rng) => math.sin(t * 880 * math.pi * 2) * (1 - p) * 0.4),
   });
   ```

2. **Open the device** once, at start-up. It returns false where there is
   no audio, and the bank then stays silent.

   ```dart
   WidgetsFlutterBinding.ensureInitialized();
   await bank.init();
   ```

3. **Play by name.** `volumeDb` 0 is full and -6 is about half.

   ```dart
   bank.play('break_${SoundFamily.stone}', volumeDb: -3);
   ```

4. **Music (optional):** `MusicDirector({'day': 'assets/day.ogg', 'night': 'assets/night.ogg'})`,
   then `setMood('night')` to crossfade.

5. **In tests,** pass a `SilentSounds` wherever a `SoundPlayer` is asked for.

## Example

[`example/main.dart`](example/main.dart) is a sound board: one button for
each sound. Copy it into a Flutter app's `lib/main.dart` and `flutter run`.
