import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
// flutter_scene's completion tracker: every command buffer the renderer submits
// is numbered here and marked done from its GPU completion callback.
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart' show rendererSubmissions;

/// A [Scene] whose picture reaches the screen only once the GPU has finished
/// drawing it, so no Flutter frame ever waits on the 3D render.
///
/// Why: when a Flutter frame samples the scene's texture, Metal holds that frame
/// until the scene's command buffers finish. The raster thread does not wait: it
/// keeps building the next frames, and Impeller recycles its transient buffer
/// every 4 frames with no GPU fence on Metal. That buffer carries the bytes that
/// upload new glyphs into the glyph atlas, so a held frame copies bytes a later
/// frame has already rewritten, and every label drawn from the atlas turns to
/// noise until it is rebuilt (menu buttons flickered on hover, the playground
/// panel was unreadable; worse with the 81-chunk vista, a busy GPU, or both).
/// Measured on the title vista with the GPU contended: the old path corrupted
/// every capture, this one none of seven (`--pace-probe`, ROADMAP session log).
///
/// So each frame draws the newest picture whose submissions have completed, and
/// a new scene frame is submitted only when none is in flight: flutter_scene
/// renders into a ring of two swapchain textures, and a second frame in flight
/// would write the texture on screen. The scene shows one frame late and renders
/// at most every other vsync (~60 Hz on a 120 Hz display); the world keeps
/// ticking behind it, only its picture waits.
base class PacedScene extends Scene {
  /// `--pace-probe`: print the counters every [_logEvery] painted frames.
  static bool log = false;
  static const int _logEvery = 60;

  /// Pictures submitted and not yet completed, with the id of their last
  /// submission. Holds at most one.
  final ListQueue<(int, ui.Picture)> _inFlight = ListQueue<(int, ui.Picture)>();
  ui.Picture? _shown;

  /// Scene frames submitted to the GPU.
  int rendered = 0;

  /// Flutter frames that drew a completed scene picture.
  int shown = 0;

  @override
  void render(Camera camera, ui.Canvas canvas, {ui.Rect? viewport, double? pixelRatio}) {
    final done = rendererSubmissions.completedThrough;
    while (_inFlight.isNotEmpty && _inFlight.first.$1 <= done) {
      _shown?.dispose();
      _shown = _inFlight.removeFirst().$2;
    }
    if (_inFlight.isEmpty) {
      // Recorded, not drawn: the picture only references the swapchain texture
      // and goes on screen once its submissions complete.
      final recorder = ui.PictureRecorder();
      super.render(camera, ui.Canvas(recorder), viewport: viewport ?? canvas.getLocalClipBounds(), pixelRatio: pixelRatio);
      _inFlight.add((rendererSubmissions.latestSubmission, recorder.endRecording()));
      rendered++;
    }
    final picture = _shown;
    if (picture == null) return; // the first frame is still on the GPU
    canvas.drawPicture(picture);
    shown++;
    if (log && shown % _logEvery == 0) {
      debugPrint('[probe] pace: shown=$shown rendered=$rendered');
    }
  }
}
