/// A sky that does not turn (an underworld's): no sun and no moon, the same
/// colours at every hour, an ambient of its own and the share of the baked
/// sky light that shows. Colours are `0xRRGGBB`, each channel read as linear
/// 0..1. `SkyLook.still` is how it looks.
///
/// ```dart
/// const underworld = StillSky(zenith: 0x0F0303, horizon: 0x470D08, ground: 0x1F0505, ambient: 0xFF8C6B);
/// ```
class StillSky {
  /// A sky of [zenith] overhead, [horizon] around and [ground] below it (the
  /// horizon's by default), lit by [ambient] at [ambientEnergy], with
  /// [skyLight] of the baked sky light showing (0: only block light).
  const StillSky({
    required this.zenith,
    required this.horizon,
    int? ground,
    required this.ambient,
    this.ambientEnergy = 0.55,
    this.skyLight = 0.0,
  }) : ground = ground ?? horizon,
       assert(ambientEnergy >= 0.0),
       assert(skyLight >= 0.0 && skyLight <= 1.0);

  /// The colour straight up.
  final int zenith;

  /// The colour at the horizon: the distance fog's, when no haze is given.
  final int horizon;

  /// The colour below the horizon.
  final int ground;

  /// The ambient light's colour.
  final int ambient;

  /// How strong the ambient is, as `SkyLook.at`'s energy (0.9 at midnight,
  /// 0.4 at noon).
  final double ambientEnergy;

  /// The share of the baked sky light that shows, 0..1.
  final double skyLight;
}
