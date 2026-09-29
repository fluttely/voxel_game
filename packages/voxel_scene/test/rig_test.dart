import 'dart:math' as math;

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

  test('parts posed one after the other each keep their own whole pose', () {
    final a = RigPart(Node(), Vector3(0, 1, 0))
      ..rx = 0.4
      ..ry = -1.1
      ..rz = 0.2
      ..offX = 0.1
      ..sx = 1.5;
    final b = RigPart(Node(), Vector3(2, 0, -1))
      ..ry = 2.5
      ..offZ = -0.3
      ..sz = 0.5;
    a.apply();
    b.apply();
    final wantA = Matrix4.compose(Vector3(0.1, 1, 0), eulerYXZ(0.4, -1.1, 0.2), Vector3(1.5, 1, 1));
    final wantB = Matrix4.compose(Vector3(2, 0, -1.3), eulerYXZ(0, 2.5, 0), Vector3(1, 1, 0.5));
    for (var i = 0; i < 16; i++) {
      expect(a.node.localTransform.storage[i], closeTo(wantA.storage[i], 1e-6), reason: 'a[$i]');
      expect(b.node.localTransform.storage[i], closeTo(wantB.storage[i], 1e-6), reason: 'b[$i]');
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

  test('a node body is drawn between the poses of its last two steps', () {
    final body = NodeBody()..position = Vector3(0, 0, 0);
    body.syncNode(yaw: 0.0);
    expect(body.drawnPosition, Vector3.zero(), reason: 'the first sync is where it is drawn from');
    body
      ..beginStep()
      ..position = Vector3(2, 0, 0)
      ..syncNode(yaw: 1.0);
    expect(body.node.position, Vector3(2, 0, 0), reason: 'a sync puts the node at the step\'s pose');
    body.drawNode(0.25);
    expect(body.drawnPosition.x, closeTo(0.5, 1e-6));
    expect(body.node.position.x, closeTo(0.5, 1e-6));
    final turn = eulerYXZ(0, 0.25, 0);
    for (var i = 0; i < 4; i++) {
      expect(body.node.rotation.storage[i], closeTo(turn.storage[i], 1e-5));
    }
    body.drawNode(1.0);
    expect(body.node.position.x, closeTo(2, 1e-6));
    // A step that does not move it: the frames stand at the last pose.
    body
      ..beginStep()
      ..drawNode(0.5);
    expect(body.node.position.x, closeTo(2, 1e-6));
  });

  test('a node body turns the short way round, and a snap does not glide', () {
    final body = NodeBody()..syncNode(yaw: 3.0);
    body
      ..beginStep()
      ..syncNode(yaw: -3.0) // 0.28 rad further on, across the half turn
      ..drawNode(0.5);
    final turn = eulerYXZ(0, 3.0 + (2 * math.pi - 6.0) / 2, 0);
    for (var i = 0; i < 4; i++) {
      expect(body.node.rotation.storage[i].abs(), closeTo(turn.storage[i].abs(), 1e-5));
    }
    body
      ..beginStep()
      ..position = Vector3(100, 0, 0)
      ..syncNode(snap: true)
      ..drawNode(0.1);
    expect(body.node.position.x, closeTo(100, 1e-4), reason: 'a respawn jumps');
  });
}
