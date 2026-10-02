import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test('a burst throws chips of its colour up out of the point, and they fall and are gone', () {
    final debris = DebrisParticles();
    final s = debris.system.storage;
    expect(debris.burst(Vector3(10, 64, -3), Vector3(0.5, 0.4, 0.2)), 12);
    expect(s.aliveCount, 12);
    for (var i = 0; i < s.aliveCount; i++) {
      expect(s.posX[i], closeTo(10, 0.31));
      expect(s.posY[i], inInclusiveRange(63.8, 64.4));
      expect(s.velY[i], inInclusiveRange(2.0, 4.0), reason: 'thrown up');
      expect(s.velX[i].abs(), lessThanOrEqualTo(2.0));
      expect(s.size[i], inInclusiveRange(0.08, 0.16));
      expect(s.colorR[i], inInclusiveRange(0.4, 0.55), reason: 'a shade of 0.8 to 1.1 of the colour');
      expect(s.colorA[i], 1.0);
    }
    debris.system.step(0.3);
    expect(s.aliveCount, 12);
    for (var i = 0; i < s.aliveCount; i++) {
      expect(s.velY[i], lessThan(4.0 - 9.8 * 0.25), reason: 'falling');
    }
    debris.system.step(0.25);
    debris.system.step(0.1);
    expect(s.aliveCount, 0, reason: 'gone after ${DebrisParticles.lifetime} s');
  });

  test('a full pool throws what fits, and cuts no flying chip short', () {
    final debris = DebrisParticles(capacity: 20);
    expect(debris.burst(Vector3.zero(), Vector3.all(1), count: 12), 12);
    expect(debris.burst(Vector3.zero(), Vector3.all(1), count: 12), 8);
    expect(debris.system.storage.aliveCount, 20);
    expect(() => debris.burst(Vector3.zero(), Vector3.all(1), count: 0), throwsArgumentError);
    expect(() => DebrisParticles(capacity: 0), throwsA(isA<AssertionError>()));
  });

  test('a slow burst is slower', () {
    final debris = DebrisParticles();
    debris.burst(Vector3.zero(), Vector3(1, 0.5, 0.1), count: 1, speed: 0.5);
    expect(debris.system.storage.velY[0], inInclusiveRange(1.0, 2.0));
  });
}
