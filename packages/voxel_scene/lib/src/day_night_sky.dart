import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'mirrored_camera.dart';

/// A day and night over a voxel world: a gradient sky with a sun (a moon at
/// night) casting cascaded shadows, a constant ambient that follows the day,
/// ACES tone mapping, and a linear distance fog in the horizon colour that
/// dissolves the edge of the loaded chunks into the sky.
///
/// Call [update] once a frame with the time of day; it returns how much of
/// the baked sky light shows, for `VoxelChunkView.setSkyIntensity`.
class DayNightSky {
  /// A sky over [scene], replacing its skybox, sun, tone mapping and fog.
  DayNightSky(this.scene, {this.sunScale = 0.6, this.ambientScale = 0.6, bool shadows = true, double sunStepDegrees = 0.5})
      : _sunStep = sunStepDegrees * math.pi / 180.0 {
    sky = GradientSkySource(sunSharpness: 600.0);
    scene.skybox = Skybox(sky);
    sun = SunLight(
      sky,
      castsShadow: shadows,
      shadowMaxDistance: 110.0,
      shadowMapResolution: 2048,
      shadowCascadeCount: 4,
      shadowSoftness: 0.04,
      shadowDepthBias: 0.02,
      shadowNormalBias: 0.06,
      shadowCasterFaces: MirroredCamera.shadowCasterFaces,
      shadowAmbientStrength: 0.0,
    );
    scene
      ..sunLight = sun
      ..toneMapping = ToneMappingMode.aces
      ..exposure = 1.0;
    // The flat horizon colour, not the sky sample: the constant-diffuse
    // environment has no radiance cube, so a sample would come back black.
    scene.fog
      ..enabled = true
      ..mode = FogMode.linear
      ..skyColorInfluence = 0.0
      ..maxOpacity = 1.0;
  }

  /// The scene lit.
  final Scene scene;

  /// The sky's colours and sun direction.
  late final GradientSkySource sky;

  /// The sun (and moon).
  late final SunLight sun;

  /// How strong the sun is against the baked block light.
  double sunScale;

  /// How strong the ambient is.
  double ambientScale;

  /// The sun turns in steps of this many radians, so the static shadow cache
  /// holds between steps (0 turns it smoothly and re-renders every frame).
  final double _sunStep;

  Vector3 _ambient = Vector3.all(-1);
  double _sinceAmbient = 1.0;
  double _lastTime = -1.0;

  /// How wide the fog band before [edge] metres is: a tenth of it, from 4 to
  /// 64 metres, as Minecraft's is.
  static double fogBand(double edge) => (edge / 10.0).clamp(4.0, 64.0);

  static Vector3 _mix(Vector3 a, Vector3 b, double t) => a + (b - a) * t;

  /// Lights the scene for [timeOfDay] (0 midnight, 0.25 sunrise, 0.5 noon)
  /// with the fog full at [fogDistance] metres; returns the sky light's share
  /// (1 at noon, 0.35 at night).
  ///
  /// The fog is Minecraft's: a linear band [fogBand] metres wide that ends on
  /// [fogDistance], so it hides only where the world stops and everything
  /// nearer stays clear, whatever the render distance.
  double update(double timeOfDay, {double fogDistance = 128.0}) {
    final dt = _lastTime < 0 ? 1.0 : (timeOfDay - _lastTime).abs();
    _lastTime = timeOfDay;
    _sinceAmbient += dt;
    var angle = (timeOfDay - 0.25) * math.pi * 2;
    if (_sunStep > 0.0) angle = (angle / _sunStep).roundToDouble() * _sunStep;
    final sunDir = Vector3(math.cos(angle) * 0.6, math.sin(angle), -0.5).normalized();
    final elevation = sunDir.y;
    final day = (elevation * 3.0 + 0.15).clamp(0.0, 1.0);
    final dusk = (1.0 - elevation.abs() * 5.0).clamp(0.0, 1.0);
    final sunColor = _mix(Vector3(1.0, 0.95, 0.85), Vector3(1.0, 0.55, 0.3), dusk);
    final top = _mix(Vector3(0.02, 0.03, 0.08), Vector3(0.20, 0.42, 0.85), day);
    final hor = _mix(_mix(Vector3(0.06, 0.08, 0.15), Vector3(0.62, 0.78, 0.92), day), Vector3(0.95, 0.55, 0.30), dusk * 0.8);
    sky
      ..zenithColor = top
      ..horizonColor = hor
      ..groundColor = hor * 0.9;
    if (elevation > 0.0) {
      sky.sunDirection = sunDir;
      sun
        ..color = sunColor
        ..intensity = (3.0 * 0.6 * day + 0.02) * sunScale;
      sky.sunColor = sunColor * (2.5 * day + 0.4);
    } else {
      sky.sunDirection = -sunDir;
      sun
        ..color = Vector3(0.55, 0.65, 0.95)
        ..intensity = (3.0 * 0.45 * (1.0 - day) + 0.02) * sunScale;
      sky.sunColor = Vector3(0.5, 0.6, 0.9) * 0.9;
    }
    final energy = 0.9 - 0.5 * day;
    final radiance = _mix(Vector3(0.35, 0.40, 0.60), Vector3(0.80, 0.84, 0.92), day) * (energy * 1.25 * ambientScale);
    // Rebuilding the environment is not free: only when it moved enough.
    if ((radiance - _ambient).length > 0.02 && _sinceAmbient > 0.001) {
      _ambient = radiance;
      _sinceAmbient = 0.0;
      scene.environment = EnvironmentMap.constantDiffuse(radiance);
    }
    scene.fog
      ..color = hor
      ..start = fogDistance - fogBand(fogDistance)
      ..end = fogDistance;
    return 0.35 + 0.65 * day;
  }
}
