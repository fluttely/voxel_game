import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
// flutter_scene's completion tracker: every command buffer the renderer submits
// is numbered there and marked done from its GPU completion callback. The same
// exact pin as the gpu shim the terrain material imports.
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart' show rendererSubmissions;

import 'resize_safe_scene.dart';
import 'scene_pacer.dart';

/// A [ResizeSafeScene] that, when [paced], puts a frame on screen only once
/// the GPU has finished drawing it (a [ScenePacer]).
///
/// Why: on Metal, a Flutter frame that samples the scene's texture is held
/// until the scene's command buffers finish, while the raster thread goes on
/// building the next frames; Impeller recycles the buffer that uploads new
/// glyphs every 4 frames with no GPU fence there, so a held frame copies glyph
/// bytes a later frame has rewritten, and the text over the scene turns to
/// noise until its atlas is rebuilt. It shows under load: a far view on a GPU
/// another process is using. Paced, the menus stay readable, and the price is
/// the frame: the scene shows one frame late and is rendered only on the
/// vsyncs that find the last one finished (about every other one at 120 Hz),
/// while the world behind it ticks on. The real fix belongs upstream
/// (Impeller's host buffer, or flutter_scene's `SceneView`).
///
/// A subclass measures a frame in [renderFrame], which is the render itself
/// whether paced or not. [warmUp] is never paced: its frame is offscreen and
/// thrown away, not the first one shown.
///
/// flutter_scene's own pacing ([maxGpuFramesInFlight], on by default since
/// 0.24) is off: it would re-present the last image on a frame this class
/// renders and counts, and the frame the kit measured is [ScenePacer]'s.
base class GpuPacedScene extends ResizeSafeScene {
  /// A scene, held back on a busy GPU when [paced].
  GpuPacedScene({this.paced = true}) {
    maxGpuFramesInFlight = gpuFramesInFlight;
  }

  /// The [maxGpuFramesInFlight] this scene sets: 0, flutter_scene's own
  /// pacing off. A constant, so a test without a GPU (which a [Scene] needs to
  /// be built) can read it.
  @visibleForTesting
  static const int gpuFramesInFlight = 0;

  /// Whether each frame waits for the GPU before it is shown.
  final bool paced;

  final ScenePacer _pacer = ScenePacer();
  bool _warming = false;
  int _rendered = 0, _shown = 0;

  /// Scene frames rendered, the warm-up's left out; paced, fewer than [shown].
  int get rendered => _rendered;

  /// Frames that drew a scene frame: paced, a finished one, maybe again.
  int get shown => _shown;

  @override
  void renderViews(List<RenderView> views, ui.Canvas canvas, {ui.Rect? region, double? pixelRatio}) {
    if (_warming) {
      renderFrame(views, canvas, region: region, pixelRatio: pixelRatio);
      return;
    }
    if (!paced) {
      renderFrame(views, canvas, region: region, pixelRatio: pixelRatio);
      _rendered++;
      _shown++;
      return;
    }
    // Recorded, not drawn, the picture has no clip of its own: the region is
    // the one this canvas would have given.
    final area = region ?? canvas.getLocalClipBounds();
    _pacer.paint(
      canvas,
      completed: rendererSubmissions.completedThrough,
      render: (recording) {
        renderFrame(views, recording, region: area, pixelRatio: pixelRatio);
        _rendered++;
        return rendererSubmissions.latestSubmission;
      },
    );
    if (_pacer.showing != null) _shown++;
  }

  /// Renders one frame of [views] onto [canvas]: the place to measure it.
  @protected
  void renderFrame(List<RenderView> views, ui.Canvas canvas, {ui.Rect? region, double? pixelRatio}) =>
      super.renderViews(views, canvas, region: region, pixelRatio: pixelRatio);

  /// The flag is up for the whole warm-up, its waits included: flutter_scene
  /// waits for its shaders and for the raster thread before it renders, and
  /// with [sliceBudget] between its frames. So no frame of this scene may be
  /// shown while it warms up, which is how the kit's loading stage and a
  /// `SceneView`'s own warm-up both call it.
  @override
  Future<void> warmUp(
    List<RenderView> views, {
    bool includeOffscreen = false,
    Duration? sliceBudget,
    bool allShadingTiers = false,
  }) async {
    _warming = true;
    try {
      await super.warmUp(
        views,
        includeOffscreen: includeOffscreen,
        sliceBudget: sliceBudget,
        allShadingTiers: allShadingTiers,
      );
    } finally {
      _warming = false;
    }
  }

  /// Lets go of the pictures held back, then of the scene's render targets
  /// ([Scene.dispose]). The scene is not drawn after this: a render throws.
  @override
  void dispose() {
    _pacer.dispose();
    super.dispose();
  }
}
