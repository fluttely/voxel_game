import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sound_recipes/sound_recipes.dart';

void main() {
  test('a recipe renders to a mono 16-bit WAV of its length', () {
    final bytes = renderWav(SoundRecipe(0.5, (t, p, r) => 0.5), rate: 8000);
    final d = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(d.getUint16(22, Endian.little), 1, reason: 'mono');
    expect(d.getUint32(24, Endian.little), 8000);
    expect(d.getUint32(40, Endian.little), 4000 * 2, reason: 'half a second of 16-bit samples');
    expect(d.getInt16(44, Endian.little), 16000);
    expect(bytes.length, 44 + 8000);
  });

  test('every stock sound is audible, never clipped past full scale, and every family is covered', () {
    for (final e in StockSounds.all.entries) {
      final bytes = renderWav(e.value);
      final d = ByteData.sublistView(bytes);
      var peak = 0;
      for (var o = 44; o < bytes.length; o += 2) {
        final v = d.getInt16(o, Endian.little).abs();
        if (v > peak) peak = v;
      }
      expect(peak, greaterThan(1000), reason: '${e.key} is audible');
      expect(peak, lessThanOrEqualTo(32000), reason: '${e.key} stays in range');
    }
    for (final f in SoundFamily.all) {
      for (final kind in ['break', 'place', 'step']) {
        expect(StockSounds.all.containsKey('${kind}_$f'), isTrue, reason: '${kind}_$f');
      }
    }
  });

  test('the same seed renders the same noise', () {
    final r = StockSounds.all['dig']!;
    expect(renderWav(r, seed: 3), renderWav(r, seed: 3));
    expect(renderWav(r, seed: 3), isNot(renderWav(r, seed: 4)));
  });

  test('a silent player remembers what it was asked', () {
    final s = SilentSounds()
      ..play('dig')
      ..play('hit', volumeDb: -6);
    expect(s.played, ['dig', 'hit']);
  });
}
