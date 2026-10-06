# Changelog

## Unreleased

**Breaking**

- `SoundBank.dispose` no longer closes the audio device: it frees the bank's own sounds
  and lets go of its hold, and the device closes when no one holds it.
- `SoundBank.init` returns false, silently, only when the device does not open. A sound
  or asset that fails to load now throws instead of leaving the bank silent.

- `AudioDevice` (new): the one audio device every bank shares (KL-024). `acquire()`
  opens it for the first holder, and `release()` closes it after the last one. Every open
  and close runs in one queue, so a bank let go while another is opening never closes the
  device under it. `AudioDevice.instance` is SoLoud's `init` and `deinit`. A test sets
  `AudioDevice(open:, close:)` there and so never touches SoLoud.

## 0.4.0-dev

**Breaking**

- None: `step_sand` and `step_snow` are new sounds.

- `StockSounds` adds `step_sand` (a dry hiss of grains) and `step_snow` (a crunch): the
  footsteps of two grounds the `earth` family lumps together, for a game to name beside
  the families' `step_<family>`.

## 0.3.0-dev

- No change of its own: released with the other three, which move together.

## 0.2.0-dev

- `MusicScore` + `StockMusic`: background music with no audio files, a loop written as
  chords and an eighth-note melody (with optional wind and drips) and synthesised like any
  recipe. Six stock scores: `pastoral`, `arid`, `frozen`, `murky`, `cavern`, `infernal`.
- `MusicDirector(recipes: ...)`: a mood whose asset the app does not bundle plays its
  recipe instead, rendered once off the main isolate, so a game can ship placeholder music
  and drop real files in later. A declared asset that is not bundled and has no recipe
  now throws instead of logging.
- `MusicDirector.setGain` applies the gain to the track playing; `isPlaying` and `origin`
  (`MusicOrigin.asset` / `.recipe`) say what is playing.

## 0.1.2-dev

- Formatted by `dart format` at the 120 columns the code is written at
  (`formatter: page_width: 120` in `analysis_options.yaml`); pana took 10 pub points
  for formatting.

## 0.1.1-dev

- No change. Released with the other three packages of the kit, which move to 0.1.1-dev
  together.

## 0.1.0-dev

First version. It was called `voxel_audio` until 2026-09-19;
the name went because nothing in it has anything to do with voxels.

- `SoundRecipe` + `renderWav`: sounds written as waveform functions, rendered to WAV.
- `StockSounds`: break, place and step sounds for every block material, plus combat and interface sounds.
- `SoundBank`: plays recipes and asset files by name through `flutter_soloud`.
- `SoundPlayer` / `SilentSounds` for silent tests and servers.
- `MusicDirector`: music by mood, crossfaded.
- `StockSounds`' dartdoc no longer names the game the set was first played in.
