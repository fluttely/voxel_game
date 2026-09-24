import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'package:voxel_engine/core.dart';
import '../game/game.dart';
import '../world/voxel_world.dart';
import 'scene_body.dart';
import 'package:voxel_scene/voxel_scene.dart';

/// A rowing boat: floats on liquid, driven by whoever sits in it (F to board /
/// leave). Stage 25: the host owns every boat. A [replica] (client side) never
/// simulates — it lerps to the pose the host streams ([setNetPose]); a client
/// that boards one sends its steer input inside its pose and the host's boat
/// carries its puppet.
class Boat extends SceneBody {
  /// The local player or, on the host, a peer's puppet (stage 25).
  Object? driver;
  double throttle = 0.0;
  double steer = 0.0;
  double yaw = 0.0;
  late Game main;
  final Node _hull = Node();
  double _roll = 0.0;
  double _time = 0.0;
  bool replica = false;
  int netId = 0;

  /// Host: the pose last streamed to clients.
  Vector3? lastSent;
  double lastSentYaw = double.infinity;
  Vector3? _netTarget;
  double _netYaw = 0.0;

  void setupBoat(VoxelWorld w, Game m, Vector3 at, double heading) {
    setup(w, 0.55, 0.5);
    main = m;
    position = at.clone();
    yaw = heading;
    final v = <IVec3, Vector3>{};
    final wood = Vector3(0.55, 0.38, 0.20);
    final dark = Vector3(0.40, 0.27, 0.14);
    VoxelModel.box(v, const IVec3(-4, 0, -7), const IVec3(4, 0, 7), dark);
    VoxelModel.box(v, const IVec3(-5, 1, -8), const IVec3(-4, 3, 8), wood);
    VoxelModel.box(v, const IVec3(4, 1, -8), const IVec3(5, 3, 8), wood);
    VoxelModel.box(v, const IVec3(-4, 1, -9), const IVec3(4, 3, -8), wood);
    VoxelModel.box(v, const IVec3(-4, 1, 8), const IVec3(4, 3, 9), wood);
    VoxelModel.box(v, const IVec3(-4, 1, -1), const IVec3(4, 1, 1), dark);
    _hull.add(VoxelModelMesh.node(v, 0.1, Vector3(0.5, 0, 0.5)));
    node.add(_hull);
    syncNode();
  }

  void update(double dt) {
    if (replica) {
      final t = _netTarget;
      if (t != null) {
        final k = (dt * 12.0).clamp(0.0, 1.0);
        position = position + (t - position) * k;
        yaw = lerpAngle(yaw, _netYaw, k);
      }
      syncNode();
      _hull.rotation = eulerYXZ(0, yaw, 0);
      return;
    }
    // Stage 24: a restored boat waits for its chunk (unloaded reads as air).
    if (!world.isLoaded(IVec3.floor(position))) return;
    _time += dt;
    final feet = IVec3(position.x.floor(), (position.y + 0.15).floor(), position.z.floor());
    if (world.isLiquid(feet)) {
      velocity.y = lerpd(velocity.y, 1.6, dt * 5.0);
    } else if (inLiquid) {
      velocity.y = lerpd(velocity.y, 0.0, dt * 6.0);
    } else {
      applyGravity(dt);
    }
    if (driver != null) {
      yaw += steer * -1.7 * dt; // Godot: D (steer +1) turns toward +X, clockwise from above
      final fwd = Vector3(-math.sin(yaw), 0, -math.cos(yaw));
      final target = fwd * throttle * (inLiquid ? 6.5 : 1.5);
      velocity.x = lerpd(velocity.x, target.x, dt * 2.5);
      velocity.z = lerpd(velocity.z, target.z, dt * 2.5);
    } else {
      velocity.x = lerpd(velocity.x, 0.0, dt * 1.5);
      velocity.z = lerpd(velocity.z, 0.0, dt * 1.5);
    }
    move(dt);
    syncNode();
    _roll = lerpd(_roll, -steer * 0.12 * throttle, dt * 4.0);
    _hull.rotation = eulerYXZ(0, yaw, _roll);
    _hull.position = Vector3(0, inLiquid ? math.sin(_time * 2.0 + position.x) * 0.03 : 0.0, 0);
  }

  /// Replica: the host's latest pose; a jump beyond 8 m snaps, the rest is lerped.
  void setNetPose(Vector3 pos, double heading) {
    if (_netTarget == null || (position - pos).length > 8.0) {
      position = pos.clone();
      yaw = heading;
    }
    _netTarget = pos.clone();
    _netYaw = heading;
  }

  /// Stage 24: what the save keeps of a boat.
  Map<String, Object> toJson() => {
        'pos': [position.x, position.y, position.z],
        'yaw': yaw,
      };

  Vector3 seat() => position + Vector3(0, 0.35, 0);
}
