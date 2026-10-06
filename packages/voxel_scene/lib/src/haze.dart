import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// A fog that thickens with distance (exponential) in one colour: a
/// dimension's haze, the murk under water. [color] is `0xRRGGBB`, each
/// channel linear 0..1; [density] how fast it closes in (at 0.05 a thing 20 m
/// off is 63 % fog, at 1.2 one a metre off is 70 %).
///
/// ```dart
/// const water = Haze(0x081F47, 0.05, followsSky: true);
/// ```
class Haze {
  /// A haze of [color] thickening at [density] per metre; with [followsSky]
  /// it darkens with the sky light, as water does at night.
  const Haze(this.color, this.density, {this.followsSky = false}) : assert(density > 0.0);

  /// The colour, at a full sky light when it [followsSky].
  final int color;

  /// The fog's density per metre.
  final double density;

  /// Whether the colour darkens with the sky light: a quarter of it shows
  /// at none.
  final bool followsSky;

  /// The colour under [skyLight] (0..1, the sky light's share).
  Vector3 colorAt(double skyLight) {
    final rgb = Vector3(((color >> 16) & 0xFF) / 255.0, ((color >> 8) & 0xFF) / 255.0, (color & 0xFF) / 255.0);
    return followsSky ? rgb * (0.25 + 0.75 * skyLight) : rgb;
  }

  /// Puts this haze on [fog] under [skyLight]: exponential, from the eye.
  void applyTo(Fog fog, double skyLight) => fog
    ..mode = FogMode.exponential
    ..color = colorAt(skyLight)
    ..density = density
    ..start = 0.0;
}
