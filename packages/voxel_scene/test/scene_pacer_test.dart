import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_scene/voxel_scene.dart';

/// A pacer driven by made-up submission ids: each render submits one more.
final class _Gpu {
  final ScenePacer pacer = ScenePacer();
  int submitted = 0, completed = 0, renders = 0;

  /// One Flutter frame.
  void frame() {
    final recorder = PictureRecorder();
    pacer.paint(
      Canvas(recorder),
      completed: completed,
      render: (canvas) {
        canvas.drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint());
        renders++;
        return ++submitted;
      },
    );
    recorder.endRecording().dispose();
  }
}

void main() {
  test('nothing is shown until the first frame is finished, and none is rendered while one is in flight', () {
    final gpu = _Gpu()..frame();
    expect((gpu.renders, gpu.pacer.inFlight, gpu.pacer.showing), (1, true, null));
    gpu
      ..frame()
      ..frame();
    expect(gpu.renders, 1, reason: 'the GPU has not finished the first');
    expect(gpu.pacer.showing, isNull);
    gpu
      ..completed = 1
      ..frame();
    expect(gpu.renders, 2, reason: 'the first finished: the next is rendered at once');
    expect(gpu.pacer.showing, isNotNull);
    expect(gpu.pacer.inFlight, isTrue);
  });

  test('a picture is shown until a newer one finishes, then let go', () {
    final gpu = _Gpu()
      ..frame()
      ..completed = 1
      ..frame();
    final first = gpu.pacer.showing!;
    gpu.frame();
    expect(gpu.pacer.showing, same(first), reason: 'the second is still on the GPU');
    expect(first.debugDisposed, isFalse);
    gpu
      ..completed = 2
      ..frame();
    expect(gpu.pacer.showing, isNot(same(first)));
    expect(first.debugDisposed, isTrue);
    expect(gpu.renders, 3);
  });

  test('a frame waits for every submission of its render, not just the first', () {
    final pacer = ScenePacer();
    void frame(int completed) => pacer.paint(Canvas(PictureRecorder()), completed: completed, render: (_) => 5);
    frame(0);
    frame(4);
    expect(pacer.showing, isNull, reason: 'submissions 1..5, done through 4');
    frame(5);
    expect(pacer.showing, isNotNull);
  });

  test('dispose lets go of the shown picture and the one in flight', () {
    final gpu = _Gpu()
      ..frame()
      ..completed = 1
      ..frame();
    final shown = gpu.pacer.showing!;
    gpu.pacer.dispose();
    expect(shown.debugDisposed, isTrue);
    expect((gpu.pacer.showing, gpu.pacer.inFlight), (null, false));
  });
}
