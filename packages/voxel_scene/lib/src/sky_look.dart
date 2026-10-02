import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// How the sky looks at one time of day under one weather: the colours, the
/// sun (or the moon), the ambient and how far the fog reaches. Pure numbers,
/// so it is computed and checked with no GPU; `DayNightSky.update` puts it on
/// the scene.
class SkyLook {
  SkyLook._({
    required this.zenith,
    required this.horizon,
    required this.sunDirection,
    required this.sunColor,
    required this.sunIntensity,
    required this.sunDiscColor,
    required this.ambient,
    required this.skyLight,
    required this.fogReach,
  });

  /// The look at [timeOfDay] (0 midnight, 0.25 sunrise, 0.5 noon), the sun
  /// turned in steps of [sunStep] radians (0 smoothly).
  ///
  /// [overcast] (0 clear .. 1 black) is how much cloud hides the sky: the sky
  /// greys, the sun and the sky light dim, the ambient with them, and the fog
  /// closes in, as Minecraft's rain does. [flash] (0 .. 1) is a lightning bolt
  /// lighting all of it white for a moment. Throws [ArgumentError] for either
  /// out of 0..1.
  factory SkyLook.at(double timeOfDay, {double sunStep = 0.0, double overcast = 0.0, double flash = 0.0}) {
    if (!(overcast >= 0.0 && overcast <= 1.0)) throw ArgumentError.value(overcast, 'overcast', 'not in 0..1');
    if (!(flash >= 0.0 && flash <= 1.0)) throw ArgumentError.value(flash, 'flash', 'not in 0..1');
    var angle = (timeOfDay - 0.25) * math.pi * 2;
    if (sunStep > 0.0) angle = (angle / sunStep).roundToDouble() * sunStep;
    final sunDir = Vector3(math.cos(angle) * 0.6, math.sin(angle), -0.5).normalized();
    final elevation = sunDir.y;
    final day = (elevation * 3.0 + 0.15).clamp(0.0, 1.0);
    final dusk = (1.0 - elevation.abs() * 5.0).clamp(0.0, 1.0);
    var top = _mix(Vector3(0.02, 0.03, 0.08), Vector3(0.20, 0.42, 0.85), day);
    var hor = _mix(
      _mix(Vector3(0.06, 0.08, 0.15), Vector3(0.62, 0.78, 0.92), day),
      Vector3(0.95, 0.55, 0.30),
      dusk * 0.8,
    );
    if (overcast > 0.0 || flash > 0.0) {
      final white = Vector3.all(1.0);
      top = _mix(_mix(top, _overcast * (0.15 + 0.85 * day), overcast), white, flash * 0.8);
      hor = _mix(_mix(hor, _overcast * (0.2 + 0.8 * day), overcast), white, flash * 0.8);
    }
    final Vector3 sunColor, sunDisc;
    final double sunIntensity;
    if (elevation > 0.0) {
      sunColor = _mix(Vector3(1.0, 0.95, 0.85), Vector3(1.0, 0.55, 0.3), dusk);
      sunIntensity = 3.0 * 0.6 * day * (1.0 - overcast) + 0.02 + flash * 1.5;
      sunDisc = sunColor * (2.5 * day + 0.4);
    } else {
      sunDir.negate();
      sunColor = Vector3(0.55, 0.65, 0.95);
      sunIntensity = 3.0 * 0.45 * (1.0 - day) + 0.02;
      sunDisc = Vector3(0.5, 0.6, 0.9) * 0.9;
    }
    final energy = (0.9 - 0.5 * day) * (1.0 - overcast * 0.5) + flash * 0.6;
    return SkyLook._(
      zenith: top,
      horizon: hor,
      sunDirection: sunDir,
      sunColor: sunColor,
      sunIntensity: sunIntensity,
      sunDiscColor: sunDisc,
      ambient: _mix(Vector3(0.35, 0.40, 0.60), Vector3(0.80, 0.84, 0.92), day) * (energy * 1.25),
      skyLight: (0.35 + 0.65 * day) * (1.0 - overcast * 0.4),
      fogReach: 1.0 - overcast * 0.35,
    );
  }

  /// The grey a full overcast turns the sky at noon.
  static final Vector3 _overcast = Vector3(0.45, 0.48, 0.55);

  static Vector3 _mix(Vector3 a, Vector3 b, double t) => a + (b - a) * t;

  /// The colour straight up.
  final Vector3 zenith;

  /// The colour at the horizon: the ground's below it, the fog's.
  final Vector3 horizon;

  /// Toward the light: the sun by day, the moon (opposite it) by night.
  final Vector3 sunDirection;

  /// The light's colour.
  final Vector3 sunColor;

  /// The light's strength, before `DayNightSky.sunScale`.
  final double sunIntensity;

  /// The colour of the disc drawn in the sky.
  final Vector3 sunDiscColor;

  /// The ambient radiance, before `DayNightSky.ambientScale`.
  final Vector3 ambient;

  /// How much of the baked sky light shows, for
  /// `VoxelChunkView.setSkyIntensity`: 1 at a clear noon, 0.35 at night.
  final double skyLight;

  /// The share of the fog distance the fog ends at: 1 clear, less as the
  /// cloud closes the view in.
  final double fogReach;
}
