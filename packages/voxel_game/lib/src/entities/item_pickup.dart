import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import 'game_entity.dart';

/// An item lying in the world: it falls, spins, is pulled toward a player
/// within [magnet] metres and picked up within [reach], after [delay]; it
/// vanishes after [life] seconds.
class ItemPickup extends GameEntity {
  /// [count] of item [item] at [at], thrown with [throwVelocity].
  ItemPickup(this.item, this.count, Vector3 at, {Vector3? throwVelocity}) {
    position = at.clone();
    velocity = throwVelocity?.clone() ?? Vector3.zero();
    halfWidth = 0.125;
    height = 0.25;
  }

  /// The item.
  final String item;

  /// How many.
  int count;

  /// How far a player pulls it.
  static const double magnet = 3.0;

  /// How near it is picked up.
  static const double reach = 1.0;

  /// Seconds before it can be picked up.
  static const double delay = 0.5;

  /// Seconds it lies before vanishing.
  static const double life = 300.0;

  double _age = 0.0;

  @override
  void attached(VoxelGame game) {
    setup(game.world, 0.125, 0.25);
    if (game.headless) return;
    final t = game.items[item];
    node.add(Node(mesh: Mesh(PickupModel.of(t.r, t.g, t.b).geometry, VoxelModelMesh.material())));
  }

  @override
  void tick(VoxelGame game, double dt) {
    _age += dt;
    if (_age > life) {
      removed = true;
      return;
    }
    final p = game.player;
    final to = p.centre() - centre();
    final d = to.length;
    if (!p.isDead && _age > delay && d < magnet) {
      if (d < reach) {
        final left = p.pickUp(item, count);
        if (left == 0) {
          removed = true;
          return;
        }
        count = left;
      } else {
        velocity = to / d * 6.0;
      }
    } else {
      applyGravity(dt);
      if (onFloor) {
        velocity.x *= 0.8;
        velocity.z *= 0.8;
      }
    }
    move(dt);
    syncNode(at: position + Vector3(0, 0.1 + math.sin(_age * 2.5) * 0.06, 0), yaw: _age * 1.8);
  }
}

/// The look of a drop of one colour, built once ([of]): its voxels, and its
/// mesh, made the first time a drop of it is drawn. Every drop of that colour
/// hangs its own node on the one mesh, so flutter_scene draws them once a
/// pass, instanced, instead of once a drop.
class PickupModel {
  PickupModel._(Vector3 color) {
    VoxelModel.box(voxels, IVec3.zero, const IVec3(3, 3, 3), color, 0.06);
  }

  /// The model of a drop coloured [r], [g], [b]: the same object for every
  /// call with the same colour, whatever item it is.
  factory PickupModel.of(double r, double g, double b) => _built[(r, g, b)] ??= PickupModel._(Vector3(r, g, b));

  static final Map<(double, double, double), PickupModel> _built = {};

  /// The cube, in voxels.
  final Map<IVec3, Vector3> voxels = {};

  /// The mesh, one for every drop of this colour.
  late final MeshGeometry geometry = VoxelModelMesh.geometry(voxels, 0.0625, Vector3(2, 0, 2))!;
}
