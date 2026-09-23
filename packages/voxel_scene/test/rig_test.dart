import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test('a rig part rests at its base and poses by angle, offset and scale', () {
    final part = RigPart(Node(), Vector3(0, 1, 0));
    expect(part.node.position, Vector3(0, 1, 0));
    part
      ..rx = 0.4
      ..offY = 0.25
      ..sy = 2
      ..apply();
    expect(part.node.position, Vector3(0, 1.25, 0));
    expect(part.node.scale, Vector3(1, 2, 1));
    final expected = eulerYXZ(0.4, 0, 0);
    for (var i = 0; i < 4; i++) {
      expect(part.node.rotation.storage[i], closeTo(expected.storage[i], 1e-6));
    }
  });

  test('a node body pushes its position into its node on sync', () {
    final body = NodeBody()..position = Vector3(3, 4, 5);
    expect(body.node.position, Vector3.zero());
    body.syncNode();
    expect(body.node.position, Vector3(3, 4, 5));
    body.position.x = 9;
    expect(body.node.position.x, 3, reason: 'a copy, not the same vector');
  });
}
