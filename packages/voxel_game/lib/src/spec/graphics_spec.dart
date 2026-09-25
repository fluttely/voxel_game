import 'package:flutter_scene/scene.dart' show AntiAliasingMode;

/// How the world is drawn: the settings that trade the look for frame time.
///
/// The GPU is what a frame waits on (`docs/VOXEL_PERF_PLAN_2026-09-25.md`), and
/// its cost is pixels times what each one does: [renderScale] and
/// [maxPixelRatio] set the pixels, [antiAliasing] and [shadows] most of the
/// work per pixel.
class GraphicsSpec {
  /// A look; the defaults are [desktop]'s.
  const GraphicsSpec({
    this.renderScale = 1.0,
    this.maxPixelRatio,
    this.antiAliasing = AntiAliasingMode.msaa,
    this.shadows = const ShadowSpec(),
  });

  /// The full look: the screen's own pixels, 4× multisampling, four shadow
  /// cascades of 2048².
  static const GraphicsSpec desktop = GraphicsSpec();

  /// A phone's: at most 1.5 pixels a point, FXAA instead of multisampling, two
  /// cascades of 1024² over 48 m, and a sun that steps 2° at a time.
  static const GraphicsSpec phone = GraphicsSpec(
    maxPixelRatio: 1.5,
    antiAliasing: AntiAliasingMode.fxaa,
    shadows: ShadowSpec(cascades: 2, resolution: 1024, distance: 48.0, sunStepDegrees: 2.0),
  );

  /// The share of the screen's resolution the world is drawn at, per axis:
  /// 0.75 draws 56% of the pixels. The HUD stays sharp.
  final double renderScale;

  /// The most pixels per logical point the world is drawn at, whatever the
  /// screen's own ratio; null for no limit.
  final double? maxPixelRatio;

  /// How edges are smoothed. flutter_scene takes back a mode the GPU lacks
  /// (multisampling on a backend without it) by asserting.
  final AntiAliasingMode antiAliasing;

  /// The sun's shadows.
  final ShadowSpec shadows;

  /// The scale flutter_scene draws at on a screen of [devicePixelRatio]:
  /// [renderScale], lowered as far as [maxPixelRatio] asks.
  double sceneScale(double devicePixelRatio) {
    final cap = maxPixelRatio;
    if (cap == null || devicePixelRatio * renderScale <= cap) return renderScale;
    return cap / devicePixelRatio;
  }
}

/// The sun's cascaded shadows.
class ShadowSpec {
  /// Shadows; the defaults are [GraphicsSpec.desktop]'s.
  const ShadowSpec({
    this.enabled = true,
    this.cascades = 4,
    this.resolution = 2048,
    this.distance = 110.0,
    this.sunStepDegrees = 0.5,
  });

  /// No shadows: the sun still lights, nothing is drawn from it.
  static const ShadowSpec off = ShadowSpec(enabled: false);

  /// Whether the sun casts shadows.
  final bool enabled;

  /// How many cascades split [distance], 1..4.
  final int cascades;

  /// Each cascade's side in texels.
  final int resolution;

  /// How far from the camera shadows are drawn, in metres.
  final double distance;

  /// The sun turns in steps of this many degrees, and every step re-renders
  /// the shadow cascades: a larger step is fewer of those frames (0 turns it
  /// smoothly and re-renders every frame).
  final double sunStepDegrees;
}
