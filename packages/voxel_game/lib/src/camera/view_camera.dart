import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../player/player_spec.dart';
import 'shoulder_orbit.dart';
import 'view_bob.dart';

/// The player's camera: the eye in first person, a [ShoulderOrbit] in third
/// person that is pulled in by walls, and a [ViewBob] on foot.
class ViewCamera {
  /// The third-person seat.
  final ShoulderOrbit orbit = ShoulderOrbit();

  /// The walk's sway of the eye.
  final ViewBob viewBob = ViewBob();

  /// Whether the view bobs.
  bool bob = true;

  double _lastTime = -1.0;
  final math.Random _jolt = math.Random(7);

  /// This frame's camera for [game]'s player.
  Camera camera(VoxelGame game) {
    final p = game.player;
    final dt = _lastTime < 0 ? 0.0 : math.max(0.0, game.time - _lastTime);
    _lastTime = game.time;
    final yaw = p.yaw, pitch = p.pitch;
    final fwd = p.forward;
    final right = Vector3(math.cos(yaw), 0, -math.sin(yaw));
    final up = Vector3(math.sin(pitch) * math.sin(yaw), math.cos(pitch), math.sin(pitch) * math.cos(yaw));
    final speed = math.sqrt(p.velocity.x * p.velocity.x + p.velocity.z * p.velocity.z);
    viewBob.update(
      dt,
      walking: p.onFloor && speed > 0.6,
      speed: speed,
      walkSpeed: p.spec.walkSpeed,
      right: right,
      up: up,
      enabled: bob,
    );
    var sway = viewBob.offset;
    // A hit jolts the eye (never the aim) and dies out.
    if (p.hurtFlash > 0.0) {
      final k = 0.08 * p.hurtFlash;
      sway += right * ((_jolt.nextDouble() * 2 - 1) * k) + up * ((_jolt.nextDouble() * 2 - 1) * k);
    }
    final Vector3 eye;
    if (p.cameraMode == CameraMode.firstPerson) {
      eye = p.eyePosition + sway;
    } else {
      final pivot = p.position + Vector3(0, 1.5, 0);
      final back = -fwd;
      final world = game.world;
      bool clearCell(int x, int y, int z) {
        if (y < 0) return false;
        final b = world.getBlockXYZ(x, y, z);
        return !(world.table.isOpaque(b) || world.table.isSolid(b));
      }

      orbit.settle(dt, pivot: pivot, right: right, up: up, back: back, jitter: sway, cellIsClear: clearCell);
      eye = pivot + orbit.offset(right, up, back, orbit.current) + sway;
    }
    return MirroredCamera(
      position: eye,
      target: eye + fwd + up * viewBob.pitch,
      up: up + right * viewBob.roll,
      fovRadiansY: p.spec.fov * math.pi / 180.0,
      fovNear: 0.05,
      // Past the fog's end every pixel is fog: the far plane stops there (and a
      // chunk further, for the corners of the view), so the ring of loaded but
      // hidden chunks is culled instead of drawn.
      fovFar: game.viewDistance + 16.0,
    );
  }
}
