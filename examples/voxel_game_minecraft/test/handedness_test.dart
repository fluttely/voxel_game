import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/player/player.dart';
import 'package:voxel_scene/voxel_scene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The render is in Godot's handedness: world +X lands on screen-right at yaw 0,
/// strafing and the mouse follow Godot's signs, and a stairs block placed from a
/// yaw gets Godot's id.
void main() {
  const size = Size(1600, 900);

  double ndcX(Camera cam, Vector3 p) {
    final clip = cam.getViewTransform(size).transform(Vector4(p.x, p.y, p.z, 1));
    return clip.x / clip.w;
  }

  test('world +X at yaw 0 projects to positive NDC x (the plain flutter_scene camera mirrors it)', () {
    final eye = Vector3(0, 0, 0);
    final ahead = eye + Player.flatForwardFor(0.0);
    final east = Vector3(1, 0, -5);
    final godot = MirroredCamera(position: eye, target: ahead, up: Vector3(0, 1, 0));
    final plain = PerspectiveCamera(position: eye, target: ahead, up: Vector3(0, 1, 0));
    expect(ndcX(godot, east), greaterThan(0.0));
    expect(ndcX(plain, east), lessThan(0.0)); // the cause: a left-handed view
    expect(godot.worldToScreen(east, size)!.dx, greaterThan(size.width / 2));
    // Up stays up, and depth is untouched by the mirror.
    expect(godot.worldToScreen(Vector3(0, 1, -5), size)!.dy, lessThan(size.height / 2));
    final a = godot.getViewTransform(size).transform(Vector4(1, 0, -5, 1));
    final b = plain.getViewTransform(size).transform(Vector4(1, 0, -5, 1));
    expect(a.z / a.w, closeTo(b.z / b.w, 1e-9));
    // The shadow cascades cast the lens to a PerspectiveProjection.
    expect(godot.projection, isA<PerspectiveProjection>());
  });

  test("the strafe and forward vectors are Godot's (player.gd)", () {
    for (final yaw in [0.0, 0.7, math.pi / 2, -2.1, math.pi]) {
      final r = Player.rightFor(yaw), f = Player.flatForwardFor(yaw);
      expect(r.x, closeTo(math.cos(yaw), 1e-6));
      expect(r.z, closeTo(-math.sin(yaw), 1e-6));
      expect(f.x, closeTo(-math.sin(yaw), 1e-6));
      expect(f.z, closeTo(-math.cos(yaw), 1e-6));
      // right = forward x up, as in a right-handed frame.
      final cross = f.cross(Vector3(0, 1, 0));
      expect((cross - r).length, lessThan(1e-6));
    }
    expect((Player.rightFor(0.0) - Vector3(1, 0, 0)).length, lessThan(1e-6)); // D strafes toward +X at yaw 0
  });

  test('moving the mouse right turns toward screen-right (+X at yaw 0)', () {
    final yaw = Player.yawAfterMouse(0.0, 10.0, 0.003);
    expect(yaw, closeTo(-0.03, 1e-12));
    expect(Player.flatForwardFor(yaw).x, greaterThan(0.0));
    // And it still lands on the right half of the frame the old view showed.
    final eye = Vector3.zero();
    final cam = MirroredCamera(position: eye, target: eye + Player.flatForwardFor(0.0), up: Vector3(0, 1, 0));
    expect(cam.worldToScreen(eye + Player.flatForwardFor(yaw) * 5.0, size)!.dx, greaterThan(size.width / 2));
  });

  test("stairs placed from a yaw get Godot's id (facing_suffix of the flat forward)", () {
    final stairs = Blocks.indexOf('oak_stairs_n');
    const godotTable = [(0.0, 'oak_stairs_n'), (math.pi / 2, 'oak_stairs_w'), (math.pi, 'oak_stairs_s'), (-math.pi / 2, 'oak_stairs_e')];
    for (final (yaw, id) in godotTable) {
      final f = Player.flatForwardFor(yaw + 0.1); // off the diagonal tie
      expect(Blocks.idOf(Blocks.stairsFacing(stairs, f.x, f.z)), id, reason: 'yaw $yaw');
    }
  });
}
