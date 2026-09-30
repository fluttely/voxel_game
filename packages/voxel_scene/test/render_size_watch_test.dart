import 'dart:ui';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  final camera = PerspectiveCamera();
  const portrait = Rect.fromLTWH(0, 0, 412, 915);
  const landscape = Rect.fromLTWH(0, 0, 915, 412);

  test('the first render is a new size, the same one again is not', () {
    final watch = RenderSizeWatch();
    final views = [RenderView(camera: camera)];
    expect(watch.changed(views, region: portrait, pixelRatio: 3.0, renderScale: 0.5), isTrue);
    expect(watch.changed(views, region: portrait, pixelRatio: 3.0, renderScale: 0.5), isFalse);
    expect(
      watch.changed([RenderView(camera: camera)], region: portrait, pixelRatio: 3.0, renderScale: 0.5),
      isFalse,
      reason: 'a new view list of the same shape',
    );
  });

  test('a turn, a pixel ratio or a render scale is a new size, once', () {
    final watch = RenderSizeWatch();
    final views = [RenderView(camera: camera)];
    watch.changed(views, region: portrait, pixelRatio: 3.0, renderScale: 0.5);
    expect(watch.changed(views, region: landscape, pixelRatio: 3.0, renderScale: 0.5), isTrue);
    expect(watch.changed(views, region: landscape, pixelRatio: 3.0, renderScale: 0.5), isFalse);
    expect(watch.changed(views, region: landscape, pixelRatio: 2.0, renderScale: 0.5), isTrue);
    expect(watch.changed(views, region: landscape, pixelRatio: 2.0, renderScale: 0.75), isTrue);
    expect(watch.changed(views, region: landscape, pixelRatio: 2.0, renderScale: 0.75), isFalse);
  });

  test("a view's viewport or scale is a new size, and so is another view", () {
    final watch = RenderSizeWatch();
    watch.changed([RenderView(camera: camera)], region: landscape, pixelRatio: 2.0, renderScale: 1.0);
    const half = Rect.fromLTWH(0, 0, 0.5, 1);
    expect(
      watch.changed(
        [RenderView(camera: camera, viewport: half)],
        region: landscape,
        pixelRatio: 2.0,
        renderScale: 1.0,
      ),
      isTrue,
    );
    expect(
      watch.changed(
        [RenderView(camera: camera, viewport: half, renderScale: 0.5)],
        region: landscape,
        pixelRatio: 2.0,
        renderScale: 1.0,
      ),
      isTrue,
    );
    expect(
      watch.changed(
        [RenderView(camera: camera, viewport: half, renderScale: 0.5), RenderView(camera: camera)],
        region: landscape,
        pixelRatio: 2.0,
        renderScale: 1.0,
      ),
      isTrue,
    );
  });
}
