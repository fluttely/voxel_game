import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test('the fog band is a tenth of the edge, from 4 to 64 metres', () {
    expect(DayNightSky.fogBand(128.0), closeTo(12.8, 1e-9));
    expect(DayNightSky.fogBand(32.0), 4.0);
    expect(DayNightSky.fogBand(1024.0), 64.0);
  });
}
