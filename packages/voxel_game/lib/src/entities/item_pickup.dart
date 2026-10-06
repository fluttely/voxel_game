import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart' show ItemStack;
import 'package:voxel_engine/core.dart' show IVec3;
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../net/remote_player.dart';
import 'game_entity.dart';

/// A stack lying in the world: it falls, spins, is pulled toward the nearest
/// player within [magnet] metres whose bag takes some of it, and picked up
/// within [reach], after [wait]; it vanishes after [life] seconds. It is the
/// [stack] that left a slot, its wear and bonus kept. On the authority the
/// players are its own and the other players' (a peer's bag as declared,
/// what it reaches handed over through `RemotePlayer.give`); a client draws
/// the host's drops as [replica]s.
class ItemPickup extends GameEntity {
  /// [stack] at [at], thrown with [throwVelocity], waiting [wait] seconds
  /// before a player can take it.
  ItemPickup(this.stack, Vector3 at, {Vector3? throwVelocity, this.wait = delay}) : _netTo = at.clone() {
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

  /// Seconds before a drop can be picked up, unless it says otherwise.
  static const double delay = 0.5;

  /// Seconds before this one can be picked up.
  final double wait;

  /// The host's number for it, which its replicas share; 0 for a drop no
  /// host has numbered.
  int netId = 0;

  /// A client's copy of the host's drop: it only goes where the host says
  /// ([setNetPose]) and spins; the host decides who takes it and when it goes.
  bool replica = false;

  Vector3 _netTo;

  /// Where the host says this replica is.
  void setNetPose(Vector3 at) => _netTo = at.clone();

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
    if (replica) {
      position = position + (_netTo - position) * math.min(1.0, dt * 12.0);
      _show();
      return;
    }
    if (_age > life) {
      removed = true;
      return;
    }
    final p = game.player;
    final here = centre();
    var nearest = !p.isDead && p.inventory.roomForStack(stack) > 0 ? p.centre().distanceTo(here) : double.infinity;
    RemotePlayer? peer;
    if (game.authority) {
      for (final r in game.playersHere) {
        if (r.isDead || r.roomFor(stack) == 0) continue;
        final d = r.centre().distanceTo(here);
        if (d < nearest) {
          nearest = d;
          peer = r;
        }
      }
    }
    if (_age > wait && nearest < magnet) {
      if (nearest < reach) {
        final left = peer == null ? p.pickUpStack(stack) : _give(peer);
        if (left == 0) {
          removed = true;
          return;
        }
        stack.count = left;
      } else {
        velocity = ((peer?.centre() ?? p.centre()) - here) / nearest * 6.0;
      }
    } else if (game.world.isLoaded(IVec3.floor(position))) {
      applyGravity(dt);
      if (onFloor) {
        velocity.x *= 0.8;
        velocity.z *= 0.8;
      }
    } else {
      // No world here (a far client's drop on the host): an unloaded cell
      // reads as air, so it waits where it is instead of falling through.
      velocity.setZero();
    }
    move(dt);
    _show();
  }

  /// Hands [peer] what its bag takes of the stack; returns how many are left.
  int _give(RemotePlayer peer) {
    final room = peer.roomFor(stack);
    peer.give(stack.copy()..count = room);
    return stack.count - room;
  }

  void _show() => syncNode(at: position + Vector3(0, 0.1 + math.sin(_age * 2.5) * 0.06, 0), yaw: _age * 1.8);
}
