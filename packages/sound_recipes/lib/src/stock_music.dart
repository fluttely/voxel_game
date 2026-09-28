import 'dart:math' as math;

import 'wav.dart';

const double _tau = math.pi * 2;

double _hz(int midi) => 440.0 * math.pow(2.0, (midi - 69) / 12.0).toDouble();

/// A loop of music written as notes: one chord a bar, held as a pad, a bass
/// on the chord's root every beat, and a [melody] of eighth notes over it.
/// Its length is a whole number of bars, and every voice fades to silence
/// before the loop point, so it loops without a click.
class MusicScore {
  /// A score at [bpm].
  const MusicScore({
    required this.bpm,
    required this.chords,
    required this.melody,
    this.pad = 0.16,
    this.bass = 0.18,
    this.lead = 0.2,
    this.bell = false,
    this.wind = 0.0,
    this.drips = 0.0,
  });

  /// Beats a minute; a bar is four beats.
  final double bpm;

  /// One chord a bar, as MIDI note numbers (60 is middle C); the first is its root.
  final List<List<int>> chords;

  /// Eighth notes, as MIDI note numbers; null rests. Loops over the chords.
  final List<int?> melody;

  /// Loudness of the held chord.
  final double pad;

  /// Loudness of the bass, the chord's root an octave down, once a beat.
  final double bass;

  /// Loudness of the melody.
  final double lead;

  /// Whether the melody rings like a bell (long decay, inharmonic overtone)
  /// instead of a pluck.
  final bool bell;

  /// Loudness of a slow low-passed noise, like wind.
  final double wind;

  /// Loudness of random water drips.
  final double drips;

  /// Seconds the loop lasts.
  double get seconds => chords.length * 4 * 60.0 / bpm;

  /// The score as a recipe, rendered sample by sample in order (the wind's
  /// filter keeps its state between samples).
  SoundRecipe toRecipe() {
    final beat = 60.0 / bpm;
    final bar = beat * 4;
    final step = beat / 2;
    final total = seconds;
    const edge = 0.35;
    var windState = 0.0;
    var last = 0.0;
    var dripAt = -1.0;
    var dripHz = 0.0;
    return SoundRecipe(total, (t, p, rng) {
      final b = (t / bar).floor().clamp(0, chords.length - 1);
      final chord = chords[b];
      final inBar = t - b * bar;
      final padEnv = math.min(1.0, inBar / edge) * math.min(1.0, (bar - inBar) / edge);
      var padSum = 0.0;
      for (final n in chord) {
        final f = _hz(n);
        padSum += math.sin(t * f * _tau) + 0.3 * math.sin(t * f * 1.003 * _tau) + 0.12 * math.sin(t * f * 2 * _tau);
      }
      var v = padSum / chord.length * padEnv * pad;

      final inBeat = t % beat;
      final bassEnv = math.min(1.0, inBeat / 0.01) * math.exp(-inBeat * 3.0) * math.min(1.0, (total - t) / 0.05);
      final bf = _hz(chord.first - 12);
      v += (math.sin(t * bf * _tau) + 0.25 * math.sin(t * bf * 2 * _tau)) * bassEnv * bass;

      final s = (t / step).floor();
      final note = melody[s % melody.length];
      if (note != null) {
        final inStep = t - s * step;
        final tail = total - s * step;
        final f = _hz(note);
        final decay = bell ? 1.6 : 5.0;
        final env = math.min(1.0, inStep / 0.008) * math.exp(-inStep * decay) * math.min(1.0, (tail - inStep) / 0.05);
        final tone = bell
            ? math.sin(t * f * _tau) + 0.35 * math.sin(t * f * 2.76 * _tau) * math.exp(-inStep * 4.0)
            : math.sin(t * f * _tau) + 0.3 * math.sin(t * f * 2 * _tau) + 0.1 * math.sin(t * f * 3 * _tau);
        v += tone * env * lead;
      }

      if (wind > 0) {
        windState += (rng.nextDouble() * 2.0 - 1.0 - windState) * 0.02;
        final swell = 0.6 + 0.4 * math.sin(p * _tau * 2);
        v += windState * 4.0 * swell * math.sin(p * math.pi) * wind;
      }

      if (drips > 0) {
        if (t - dripAt > 0.05 && total - t > 0.2 && rng.nextDouble() < 2.5 * (t - last)) {
          dripAt = t;
          dripHz = 900 + rng.nextDouble() * 900;
        }
        final age = t - dripAt;
        if (dripAt >= 0 && age < 0.15) v += math.sin(age * (dripHz + age * 4000) * _tau) * math.exp(-age * 40) * drips;
      }
      last = t;
      return v;
    });
  }
}

/// Stock background music, every loop synthesised from a [MusicScore]: one
/// for each broad mood a game's places have.
abstract final class StockMusic {
  /// Open fields by day: C major, unhurried.
  static const MusicScore pastoral = MusicScore(
    bpm: 84,
    chords: [
      [60, 64, 67],
      [55, 59, 62],
      [57, 60, 64],
      [53, 57, 60],
    ],
    melody: [
      72,
      null,
      76,
      74,
      72,
      null,
      67,
      null,
      71,
      null,
      74,
      null,
      67,
      null,
      null,
      null,
      69,
      null,
      72,
      76,
      74,
      null,
      72,
      null,
      69,
      null,
      72,
      null,
      65,
      null,
      null,
      null,
    ],
  );

  /// Sand and heat: D with a flattened second, a slow sway.
  static const MusicScore arid = MusicScore(
    bpm: 72,
    chords: [
      [50, 54, 57],
      [51, 55, 58],
      [50, 54, 57],
      [48, 52, 55],
    ],
    melody: [
      62,
      null,
      63,
      null,
      66,
      67,
      66,
      null,
      63,
      null,
      62,
      null,
      null,
      null,
      null,
      null,
      69,
      null,
      67,
      66,
      63,
      null,
      62,
      null,
      60,
      null,
      62,
      null,
      null,
      null,
      null,
      null,
    ],
    wind: 0.05,
  );

  /// Snow and ice: E minor, sparse bells.
  static const MusicScore frozen = MusicScore(
    bpm: 60,
    chords: [
      [52, 55, 59, 66],
      [48, 52, 55, 59],
      [55, 59, 62, 66],
      [50, 54, 57, 62],
    ],
    melody: [
      83,
      null,
      null,
      null,
      79,
      null,
      null,
      null,
      78,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      76,
      null,
      null,
      null,
      79,
      null,
      81,
      null,
      78,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
    ],
    bell: true,
    lead: 0.14,
    bass: 0.1,
    wind: 0.06,
  );

  /// Wetlands and rain: A minor, low, dripping.
  static const MusicScore murky = MusicScore(
    bpm: 64,
    chords: [
      [45, 48, 52],
      [41, 45, 48],
      [50, 53, 57],
      [52, 56, 59],
    ],
    melody: [
      64,
      null,
      null,
      60,
      62,
      null,
      null,
      null,
      57,
      null,
      60,
      null,
      null,
      null,
      null,
      null,
      65,
      null,
      64,
      null,
      62,
      null,
      60,
      null,
      59,
      null,
      null,
      null,
      56,
      null,
      null,
      null,
    ],
    lead: 0.16,
    drips: 0.12,
  );

  /// Underground: C minor, a drone and a few far notes.
  static const MusicScore cavern = MusicScore(
    bpm: 50,
    chords: [
      [36, 43, 48, 51],
      [32, 39, 44, 48],
      [36, 43, 48, 51],
      [31, 38, 43, 47],
    ],
    melody: [
      null,
      null,
      63,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      67,
      null,
      62,
      null,
      null,
      null,
      null,
      null,
      60,
      null,
      null,
      null,
      null,
      null,
      59,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
    ],
    bell: true,
    pad: 0.2,
    bass: 0.12,
    lead: 0.1,
    drips: 0.06,
  );

  /// Fire and danger: F minor, a driving bass.
  static const MusicScore infernal = MusicScore(
    bpm: 96,
    chords: [
      [41, 44, 48],
      [37, 41, 44],
      [46, 49, 53],
      [48, 52, 55],
    ],
    melody: [
      65,
      68,
      72,
      68,
      65,
      null,
      63,
      null,
      61,
      65,
      68,
      65,
      61,
      null,
      60,
      null,
      58,
      61,
      65,
      61,
      58,
      null,
      60,
      null,
      60,
      64,
      67,
      64,
      60,
      null,
      null,
      null,
    ],
    bass: 0.26,
    lead: 0.15,
    wind: 0.04,
  );

  /// Every stock score by name.
  static const Map<String, MusicScore> all = {
    'pastoral': pastoral,
    'arid': arid,
    'frozen': frozen,
    'murky': murky,
    'cavern': cavern,
    'infernal': infernal,
  };
}
