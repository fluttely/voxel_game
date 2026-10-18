import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test('a pulse grows to its radius out of a unit sphere, easing out', () {
    expect(PulseEffects.scaleAt(0, 4), 1.0, reason: 'the unit-diameter sphere at the start');
    expect(PulseEffects.scaleAt(PulseEffects.seconds, 4), closeTo(8.0, 1e-9), reason: 'twice the radius it reaches');
    expect(PulseEffects.scaleAt(PulseEffects.seconds / 2, 4), closeTo(1 + 7 * 0.875, 1e-9), reason: '1 - (1 - 0.5)^3');
    expect(PulseEffects.scaleAt(PulseEffects.seconds * 3, 4), closeTo(8.0, 1e-9), reason: 'held at the end');
  });

  test('a pulse fades from its alpha to nothing over its seconds', () {
    expect(PulseEffects.alphaAt(0), PulseEffects.alpha);
    expect(PulseEffects.alpha, 0.55);
    expect(PulseEffects.alphaAt(PulseEffects.seconds / 2), closeTo(0.275, 1e-9));
    expect(PulseEffects.alphaAt(PulseEffects.seconds), 0.0);
    expect(PulseEffects.alphaAt(PulseEffects.seconds * 2), 0.0);
  });

  test('a pulse is shown where it was raised, ages and is gone past its seconds', () {
    final pulses = PulseEffects();
    pulses.add(Vector3(10, 64, -3), 0xFF8C33, 1.0);
    expect(pulses.shown.single, (at: Vector3(10, 64, -3), color: 0xFF8C33, radius: 1.0, age: 0.0));
    pulses.advance(0.2);
    expect(pulses.shown.single.age, closeTo(0.2, 1e-9));
    pulses.advance(0.2);
    expect(pulses.shown, isEmpty, reason: 'gone after ${PulseEffects.seconds} s');
  });

  test('the point it was raised at is copied, not held', () {
    final pulses = PulseEffects();
    final at = Vector3(1, 2, 3);
    pulses.add(at, 0x000000, 2.0);
    at.x = 99;
    expect(pulses.shown.single.at, Vector3(1, 2, 3));
  });

  test('a full pool drops the oldest pulse', () {
    final pulses = PulseEffects(capacity: 2);
    pulses
      ..add(Vector3.zero(), 0x111111, 1.0)
      ..add(Vector3.zero(), 0x222222, 1.0)
      ..add(Vector3.zero(), 0x333333, 1.0);
    expect(pulses.shown.map((p) => p.color), [0x222222, 0x333333]);
  });

  test('a radius not above 0, a colour out of 0xRRGGBB and an empty pool throw', () {
    final pulses = PulseEffects();
    expect(() => pulses.add(Vector3.zero(), 0xFFFFFF, 0.0), throwsArgumentError);
    expect(() => pulses.add(Vector3.zero(), 0xFFFFFF, -1.0), throwsArgumentError);
    expect(() => pulses.add(Vector3.zero(), -1, 1.0), throwsArgumentError);
    expect(() => pulses.add(Vector3.zero(), 0x1000000, 1.0), throwsArgumentError);
    expect(pulses.shown, isEmpty);
    expect(() => PulseEffects(capacity: 0), throwsA(isA<AssertionError>()));
  });
}
