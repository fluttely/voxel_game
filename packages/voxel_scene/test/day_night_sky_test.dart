import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test('the fog band is a tenth of the edge, from 4 to 64 metres', () {
    expect(DayNightSky.fogBand(128.0), closeTo(12.8, 1e-9));
    expect(DayNightSky.fogBand(32.0), 4.0);
    expect(DayNightSky.fogBand(1024.0), 64.0);
  });

  group('SkyLook', () {
    test('a clear noon is the bright day, a clear midnight the moonlit night', () {
      final noon = SkyLook.at(0.5), night = SkyLook.at(0.0);
      expect(noon.skyLight, closeTo(1.0, 1e-9));
      expect(night.skyLight, closeTo(0.35, 1e-9));
      expect(noon.fogReach, 1.0);
      expect(noon.sunDirection.y, greaterThan(0.0));
      expect(night.sunDirection.y, greaterThan(0.0), reason: 'the moon, opposite the sun, is up');
      expect(noon.zenith.b, greaterThan(noon.zenith.r), reason: 'a blue sky');
    });

    test('cloud greys the sky, dims the light and closes the fog in', () {
      final clear = SkyLook.at(0.5), storm = SkyLook.at(0.5, overcast: 0.75);
      expect(storm.sunIntensity, lessThan(clear.sunIntensity * 0.3));
      expect(storm.skyLight, closeTo(1.0 - 0.75 * 0.4, 1e-9));
      expect(storm.ambient.length, lessThan(clear.ambient.length));
      expect(storm.fogReach, closeTo(1.0 - 0.75 * 0.35, 1e-9));
      final spread = storm.zenith.b - storm.zenith.r, clearSpread = clear.zenith.b - clear.zenith.r;
      expect(spread, lessThan(clearSpread / 2), reason: 'the blue goes grey');
    });

    test('a bolt lights it all white for a moment', () {
      final storm = SkyLook.at(0.5, overcast: 0.75), bolt = SkyLook.at(0.5, overcast: 0.75, flash: 1.0);
      expect(bolt.sunIntensity, greaterThan(storm.sunIntensity + 1.0));
      expect(bolt.ambient.length, greaterThan(storm.ambient.length));
      expect(bolt.horizon.r, greaterThan(0.85));
      expect(bolt.zenith.r, greaterThan(0.85));
    });

    test('a share out of 0..1 throws', () {
      expect(() => SkyLook.at(0.5, overcast: 1.5), throwsArgumentError);
      expect(() => SkyLook.at(0.5, flash: -0.1), throwsArgumentError);
      expect(() => SkyLook.at(0.5, overcast: double.nan), throwsArgumentError);
    });
  });

  group('a dimension\'s own sky and haze', () {
    const underworld = StillSky(zenith: 0x0F0303, horizon: 0x470D08, ground: 0x1F0505, ambient: 0xFF8C6B);

    test('a still sky has no sun, its own colours, and looks the same at every hour', () {
      final look = SkyLook.still(underworld);
      expect(look.sunIntensity, 0.0);
      expect(look.sunDiscColor.length, 0.0);
      expect(look.skyLight, 0.0);
      expect(look.fogReach, 1.0);
      expect(look.horizon.r, closeTo(0x47 / 255, 1e-6));
      expect(look.ground.r, closeTo(0x1F / 255, 1e-6));
      expect(look.ambient.r, closeTo(0.55 * 1.25, 1e-6), reason: 'the ambient at its energy, as SkyLook.at counts it');
      expect(const StillSky(zenith: 0, horizon: 0x102030, ambient: 0).ground, 0x102030, reason: 'the horizon\'s');
    });

    test('a haze is an exponential fog from the eye; one that follows the sky darkens with it', () {
      const water = Haze(0x081F47, 0.05, followsSky: true);
      final fog = Fog()
        ..mode = FogMode.linear
        ..start = 100.0;
      water.applyTo(fog, 1.0);
      expect(fog.mode, FogMode.exponential);
      expect(fog.start, 0.0);
      expect(fog.density, 0.05);
      expect(fog.color.b, closeTo(0x47 / 255, 1e-6));
      expect(water.colorAt(0.0).b, closeTo(0x47 / 255 * 0.25, 1e-6), reason: 'a quarter at no sky light');
      expect(
        const Haze(0x4C0F0A, 0.014).colorAt(0.0).r,
        closeTo(0x4C / 255, 1e-6),
        reason: 'a haze of its own keeps its colour',
      );
    });
  });
}
