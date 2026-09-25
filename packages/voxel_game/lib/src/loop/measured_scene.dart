import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// flutter_scene's completion tracker: every command buffer the renderer submits
// is numbered there and marked done from its GPU completion callback. The kit
// pins flutter_scene exactly, as voxel_scene does for its gpu shim.
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart' show rendererSubmissions;
// The same pin: the shim is the one GPU context flutter_scene submits to.
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

import 'frame_stats.dart';

/// A [Scene] that reports to [stats] how long each frame took to encode (on
/// the UI thread, where flutter_scene records its GPU commands), how long the
/// GPU took to finish it, and how many ticks later that was seen.
///
/// The GPU time is an empty command buffer submitted after the frame's own:
/// one queue runs its buffers in order, so its completion callback marks the
/// end of the frame's work. It is measured from the end of the encoding to the
/// callback reaching the UI isolate, so it is an upper bound, and it includes
/// any wait behind the previous frame when the GPU is behind.
final class MeasuredScene extends Scene {
  /// A scene reporting to [stats].
  MeasuredScene(this.stats);

  /// Where the samples go.
  final FrameStats stats;

  final Stopwatch _watch = Stopwatch();
  final Stopwatch _clock = Stopwatch()..start();
  final ListQueue<(int submission, int frame)> _inFlight = ListQueue();
  int _frame = 0;

  @override
  void renderViews(List<RenderView> views, ui.Canvas canvas, {ui.Rect? region, double? pixelRatio}) {
    _frame++;
    final done = rendererSubmissions.completedThrough;
    while (_inFlight.isNotEmpty && _inFlight.first.$1 <= done) {
      stats.addGpuLag(_frame - _inFlight.removeFirst().$2);
    }
    _watch
      ..reset()
      ..start();
    super.renderViews(views, canvas, region: region, pixelRatio: pixelRatio);
    _watch.stop();
    stats.addEncode(_watch.elapsedMicroseconds / 1000.0);
    _inFlight.add((rendererSubmissions.latestSubmission, _frame));
    final submitted = _clock.elapsedMicroseconds;
    gpu.gpuContext.createCommandBuffer().submit(
      completionCallback: (_) => stats.addGpu((_clock.elapsedMicroseconds - submitted) / 1000.0),
    );
  }
}
