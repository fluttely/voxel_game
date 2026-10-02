import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart' show ItemStack;
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import 'game_entity.dart';

/// A stack lying in the world: it falls, spins, is pulled toward a player
/// within [magnet] metres and picked up within [reach], after [delay]; it
/// vanishes after [life] seconds. It is the [stack] that left a slot, its
/// wear and bonus kept.
class ItemPickup extends GameEntity {
  /// [stack] at [at], thrown with [throwVelocity].
  ItemPickup(this.stack, Vector3 at, {Vector3? throwVelocity}) {
    position = at.clone();
    velocity = throwVelocity?.clone() ?? Vector3.zero();
    halfWidth = 0.125;
    height = 0.25;
  }

  /// What lies here.
  final ItemStack stack;

  /// The item.
  String get item => stack.id;

  /// How many.
  int get count => stack.count;

  /// How far a player pulls it.
  static const double magnet = 3.0;

  /// How near it is picked up.
  static const double reach = 1.0;

  /// Seconds before it can be picked up.
  static const double delay = 0.5;

  /// Seconds it lies before vanishing.
  static const double life = 300.0;

  /// How much of its held size a drop is drawn at: a block's item a quarter
  /// of a block a side.
  static const double size = 0.7;

  double _age = 0.0;

  @override
  void attached(VoxelGame game) {
    setup(game.world, 0.125, 0.25);
    if (game.headless) return;
    node.add(_dropNode(ItemMesh.of(game.itemModel(item))));
  }

  /// A node drawing [mesh] as a drop: [size] times its held size, standing
  /// on its floor and turning about its own middle, whatever it is held by.
  static Node _dropNode(ItemMesh mesh) {
    final b = mesh.model.bounds();
    final c = b.center;
    return mesh.node()
      ..scale = Vector3.all(size)
      ..position = Vector3(-c.x * size, -b.min.y * size, -c.z * size);
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
        final left = p.pickUpStack(stack);
        if (left == 0) {
          removed = true;
          return;
        }
        stack.count = left;
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
