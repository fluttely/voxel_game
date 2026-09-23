import 'dart:ui' show Size;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  const size = Size(1600, 900);

  double ndcX(Camera cam, Vector3 p) {
    final clip = cam.getViewTransform(size).transform(Vector4(p.x, p.y, p.z, 1));
    return clip.x / clip.w;
  }

  test('world +X lands on screen-right looking down -Z; the plain camera mirrors it', () {
    final eye = Vector3.zero(), ahead = Vector3(0, 0, -1), east = Vector3(1, 0, -5);
    final mirrored = MirroredCamera(position: eye, target: ahead);
    final plain = PerspectiveCamera(position: eye, target: ahead);
    expect(ndcX(mirrored, east), greaterThan(0.0));
    expect(ndcX(plain, east), lessThan(0.0));
    expect(mirrored.worldToScreen(east, size)!.dx, greaterThan(size.width / 2));
    expect(mirrored.worldToScreen(Vector3(0, 1, -5), size)!.dy, lessThan(size.height / 2), reason: 'up stays up');
    final a = mirrored.getViewTransform(size).transform(Vector4(1, 0, -5, 1));
    final b = plain.getViewTransform(size).transform(Vector4(1, 0, -5, 1));
    expect(a.z / a.w, closeTo(b.z / b.w, 1e-9), reason: 'depth is untouched');
  });

  test('the lens is a PerspectiveProjection, as the shadow cascades require', () {
    expect(MirroredCamera(position: Vector3(0, 0, 5), target: Vector3.zero()).projection, isA<PerspectiveProjection>());
    expect(MirroredCamera.shadowCasterFaces, ShadowCasterFaces.front);
  });

  test('a primitive is mirrored in x; its holder is not', () {
    // A mesh without primitives: no geometry reaches the GPU, which tests lack.
    final holder = MirroredCamera.primitiveNode(Mesh.primitives(primitives: []), castsShadows: false);
    expect(holder.scale, Vector3(1, 1, 1));
    expect(holder.castsShadows, isFalse);
    final child = holder.children.single;
    expect(child.scale, Vector3(-1, 1, 1));
    expect(child.castsShadows, isFalse);
  });
}
