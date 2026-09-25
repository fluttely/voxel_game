# Changelog

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
