/// Procedural game audio: sound effects synthesised to WAV at start-up (no
/// audio files), a stock set by block material, and music crossfaded by mood
/// (from files, or synthesised when a file is absent), through flutter_soloud.
library;

export 'src/audio_device.dart';
export 'src/sound_bank.dart';
export 'src/stock_music.dart';
export 'src/stock_sounds.dart';
export 'src/wav.dart';
