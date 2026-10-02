import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

void main() {
  test('a number is shown for its second, rising and then fading', () {
    final n = DamageNumbers()..add(Vector3(1, 2, 3), 4);
    expect(n.shown.single.amount, 4);
    expect(n.shown.single.at, Vector3(1, 2, 3));
    expect(DamageNumbers.risenAt(0), 0.0);
    expect(DamageNumbers.risenAt(DamageNumbers.riseSeconds), DamageNumbers.rise);
    expect(
      DamageNumbers.risenAt(DamageNumbers.riseSeconds / 2),
      greaterThan(DamageNumbers.rise / 2),
      reason: 'it eases',
    );
    expect(DamageNumbers.opacityAt(DamageNumbers.fadeDelay), 1.0);
    expect(DamageNumbers.opacityAt((DamageNumbers.fadeDelay + DamageNumbers.seconds) / 2), closeTo(0.5, 1e-9));
    n.advance(DamageNumbers.seconds - 0.01);
    expect(n.shown, hasLength(1));
    n.advance(0.01);
    expect(n.shown, isEmpty);
  });

  test('the oldest goes when too many are up', () {
    final n = DamageNumbers();
    for (var i = 1; i <= DamageNumbers.kept + 2; i++) {
      n.add(Vector3.zero(), i.toDouble());
    }
    expect(n.shown, hasLength(DamageNumbers.kept));
    expect(n.shown.first.amount, 3);
  });

  test('a hit deals some damage', () {
    expect(() => DamageNumbers().add(Vector3.zero(), 0), throwsArgumentError);
  });

  test('a number is written whole, or to a tenth under 10', () {
    expect(DamageNumbers.label(3), '3');
    expect(DamageNumbers.label(2.5), '2.5');
    expect(DamageNumbers.label(12.4), '12');
    expect(DamageNumbers.label(0.96), '1');
  });

  test("a critical blow's number is marked, and says so with a !", () {
    final n = DamageNumbers()
      ..add(Vector3.zero(), 2)
      ..add(Vector3.zero(), 3, crit: true);
    expect([for (final d in n.shown) d.crit], [false, true]);
    expect(DamageNumbers.label(3, crit: true), '3!');
    expect(DamageNumbers.label(2.5, crit: true), '2.5!');
  });
}
