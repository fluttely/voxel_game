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
base class GpuPacedScene extends ResizeSafeScene {
  /// A scene, held back on a busy GPU when [paced].
  GpuPacedScene({this.paced = true});

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

  @override
  Future<void> warmUp(List<RenderView> views, {bool includeOffscreen = false}) async {
    // Loaded first, so the flag is up only for the synchronous render the
    // warm-up does once its own await of the same future resumes.
    await Scene.initializeStaticResources();
    _warming = true;
    try {
      await super.warmUp(views, includeOffscreen: includeOffscreen);
    } finally {
      _warming = false;
    }
  }

  /// Lets go of the pictures held back. The scene is not drawn after this.
  void dispose() => _pacer.dispose();
}
