import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test('rain falls fast through the box and keeps it full', () {
    final rain = WeatherParticles.rainSystem(900);
    for (var i = 0; i < 4 * 60; i++) {
      rain.step(1 / 60);
    }
    final s = rain.storage;
    expect(s.aliveCount, greaterThan(800), reason: 'the rate replaces the drops as they land');
    expect(s.aliveCount, lessThanOrEqualTo(900));
    for (var i = 0; i < s.aliveCount; i++) {
      expect(s.velY[i], lessThan(-12.0), reason: 'a drop falls at about 16 m/s');
      expect(s.posX[i].abs(), lessThan(WeatherParticles.reach + 8.0), reason: 'a breeze slants it a little');
      expect(s.posZ[i].abs(), lessThanOrEqualTo(WeatherParticles.reach + 1e-3));
      expect(s.posY[i], greaterThan(-2.6 * WeatherParticles.height), reason: 'it dies after falling twice the height');
    }
  });

  test('snow drifts down slowly', () {
    final snow = WeatherParticles.snowSystem(500);
    for (var i = 0; i < 4 * 60; i++) {
      snow.step(1 / 60);
    }
    final s = snow.storage;
    expect(s.aliveCount, greaterThan(0));
    for (var i = 0; i < s.aliveCount; i++) {
      expect(s.velY[i], inInclusiveRange(-2.5, -1.5));
    }
  });

  test('no particles is refused', () {
    expect(() => WeatherParticles.rainSystem(0), throwsArgumentError);
  });
}
