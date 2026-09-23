import 'dart:math' as math;
import 'dart:typed_data';

/// One sample of a sound: [t] seconds in, [p] 0..1 through it, [rng] for
/// noise. Returns -1..1 (clipped).
typedef SampleFn = double Function(double t, double p, math.Random rng);

/// A sound made from a function of time: [seconds] long.
class SoundRecipe {
  /// A recipe.
  const SoundRecipe(this.seconds, this.sample);

  /// How long.
  final double seconds;

  /// The waveform.
  final SampleFn sample;
}

/// Renders [recipe] to 16-bit mono PCM WAV bytes at [rate] samples a second,
/// its noise drawn from [seed].
Uint8List renderWav(SoundRecipe recipe, {int rate = 22050, int seed = 1}) {
  final rng = math.Random(seed);
  final n = (recipe.seconds * rate).toInt();
  final bytes = ByteData(44 + n * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  bytes.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  str(36, 'data');
  bytes.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = recipe.sample(i / rate, i / n, rng).clamp(-1.0, 1.0);
    bytes.setInt16(44 + i * 2, (v * 32000).toInt(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
