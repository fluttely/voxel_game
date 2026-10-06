import 'package:voxel_scene/voxel_scene.dart';

/// A dimension's own sky (`SkySpec.dimensions`): [sky] at every hour, no sun
/// and no moon, and the fog closing in as [haze] (null: the distance fog in
/// the sky's horizon colour). Weather follows the biomes underfoot, so a
/// dimension with none declares its biomes `Precipitation.none`.
///
/// ```dart
/// sky: SkySpec(dimensions: {
///   'underworld': DimensionSky(
///     StillSky(zenith: 0x0F0303, horizon: 0x470D08, ground: 0x1F0505, ambient: 0xFF8C6B),
///     haze: Haze(0x4C0F0A, 0.014),
///   ),
/// }),
/// ```
class DimensionSky {
  /// A dimension under [sky], in [haze].
  const DimensionSky(this.sky, {this.haze});

  /// What is overhead.
  final StillSky sky;

  /// The fog, or null for the distance fog.
  final Haze? haze;
}
