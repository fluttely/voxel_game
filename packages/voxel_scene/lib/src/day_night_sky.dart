import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'mirrored_camera.dart';
import 'sky_look.dart';

/// A day and night over a voxel world: a gradient sky with a sun (a moon at
/// night) casting cascaded shadows, a constant ambient that follows the day,
/// ACES tone mapping, and a linear distance fog in the horizon colour that
/// dissolves the edge of the loaded chunks into the sky; cloud greys and
/// dims all of it and lightning flashes it white.
///
/// Call [update] once a frame with the time of day and the weather; it
/// returns how much of the baked sky light shows, for
/// `VoxelChunkView.setSkyIntensity`. The numbers are [SkyLook]'s.
class DayNightSky {
  /// A sky over [scene], replacing its skybox, sun, tone mapping and fog.
  ///
  /// The shadows are [shadowCascades] cascades of [shadowResolution]² texels
  /// splitting [shadowDistance] metres.
  DayNightSky(
    this.scene, {
    this.sunScale = 0.6,
    this.ambientScale = 0.6,
    bool shadows = true,
    int shadowCascades = 4,
    int shadowResolution = 2048,
    double shadowDistance = 110.0,
    double sunStepDegrees = 0.5,
  }) : _sunStep = sunStepDegrees * math.pi / 180.0 {
    sky = GradientSkySource(sunSharpness: 600.0);
    scene.skybox = Skybox(sky);
    sun = SunLight(
      sky,
      castsShadow: shadows,
      shadowMaxDistance: shadowDistance,
      shadowMapResolution: shadowResolution,
      shadowCascadeCount: shadowCascades,
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
  double _ambientWeather = 0.0;

  /// How wide the fog band before [edge] metres is: a tenth of it, from 4 to
  /// 64 metres, as Minecraft's is.
  static double fogBand(double edge) => (edge / 10.0).clamp(4.0, 64.0);

  /// Lights the scene for [timeOfDay] (0 midnight, 0.25 sunrise, 0.5 noon)
  /// with the fog full at [fogDistance] metres, under [overcast] cloud and a
  /// lightning [flash] (both 0..1, see [SkyLook.at]); returns the sky light's
  /// share (1 at a clear noon, 0.35 at night, less under cloud).
  ///
  /// The fog is Minecraft's: a linear band [fogBand] metres wide that ends on
  /// [fogDistance], so it hides only where the world stops and everything
  /// nearer stays clear, whatever the render distance. Cloud pulls the end in
  /// ([SkyLook.fogReach]).
  double update(double timeOfDay, {double fogDistance = 128.0, double overcast = 0.0, double flash = 0.0}) {
    final dt = _lastTime < 0 ? 1.0 : (timeOfDay - _lastTime).abs();
    _lastTime = timeOfDay;
    _sinceAmbient += dt;
    final look = SkyLook.at(timeOfDay, sunStep: _sunStep, overcast: overcast, flash: flash);
    sky
      ..zenithColor = look.zenith
      ..horizonColor = look.horizon
      ..groundColor = look.horizon * 0.9
      ..sunDirection = look.sunDirection
      ..sunColor = look.sunDiscColor;
    sun
      ..color = look.sunColor
      ..intensity = look.sunIntensity * sunScale;
    final radiance = look.ambient * ambientScale;
    // Rebuilding the environment is not free: only when it moved enough, and
    // by the day no more than once in a thousandth of one. The weather moves
    // it on a clock of its own (a bolt is over in a sixth of a second), so a
    // change of the weather's share rebuilds it whatever the day did.
    final weather = overcast + flash;
    if ((radiance - _ambient).length > 0.02 && (_sinceAmbient > 0.001 || weather != _ambientWeather)) {
      _ambient = radiance;
      _sinceAmbient = 0.0;
      _ambientWeather = weather;
      scene.environment = EnvironmentMap.constantDiffuse(radiance);
    }
    final edge = fogDistance * look.fogReach;
    scene.fog
      ..color = look.horizon
      ..start = edge - fogBand(edge)
      ..end = edge;
    return look.skyLight;
  }
}
