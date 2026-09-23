import '../noise/fast_noise_lite.dart';

int _u32(int v) => v & 0xFFFFFFFF;

/// A 32-bit hash of a world position under [seed]: the same cell gives the
/// same number on every chunk, isolate and run, which is what lets two chunks
/// agree on a tree or a structure that crosses their border. Features salt
/// [y] (or scale [x] and [z] by primes) to draw independent rolls from one
/// position.
int worldHash(int seed, int x, int y, int z) {
  var h = _u32(x * 73856093) ^ _u32(y * 19349663) ^ _u32(z * 83492791) ^ _u32(_u32(seed) * 2654435761);
  h = _u32(h);
  h ^= h >> 13;
  h = _u32(h * 0x5bd1e995);
  h ^= h >> 15;
  return h;
}

/// [a] divided by [b], rounded toward negative infinity: the region or patch a
/// coordinate falls in, negative coordinates included.
int floorDiv(int a, int b) => (a / b).floor();

/// 0 below [a], 1 above [b], and a smooth S-curve between.
double smoothstep(double a, double b, double t) {
  t = ((t - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// OpenSimplex2S noise with [octaves] of [fractal] at [frequency]: the layer
/// every height, climate and cave field here is built from.
FastNoiseLite simplexNoise(int seed, double frequency, int octaves, [FractalType fractal = FractalType.fbm]) =>
    FastNoiseLite(seed: seed)
      ..noiseType = NoiseType.openSimplex2S
      ..fractalType = fractal
      ..octaves = octaves
      ..frequency = frequency;
