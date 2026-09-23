import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../core/blocks.dart';
import '../core/items.dart';
import 'package:voxel_engine/core.dart';
import '../game/inventory.dart';
import '../game/net.dart';
import '../game/sfx.dart';
import '../player/player.dart';
import '../ui/hud.dart';
import '../world/voxel_world.dart';
import 'target.dart';
import 'scene_body.dart';
import 'voxel_mesh_builder.dart';

/// An item lying in the world: bobs, spins, is pulled to a near player and
/// picked up. Stage 21b: the host owns every drop; the host also pulls a drop
/// to a peer's puppet and hands the item over through the network. Stage 25: a
/// [replica] (client side) never simulates — it lerps to the pose the host
/// streams ([setNetPose]) and only spins; a puppet is pulled only when its
/// peer's declared bag has room.
class ItemDrop extends SceneBody {
  String itemId = '';
  int count = 1;
  int bonus = 0;
  double _age = 0.0;
  final Node _visual = Node();
  late Player _player;
  double _pickupDelay = 0.6;
  bool replica = false;
  int netId = 0;

  /// Host: the position last streamed to clients. Replica: the host's latest
  /// pose, lerped to.
  Vector3? lastSent;
  Vector3? _netTarget;

  /// Replica: the host's latest pose (stage 25); a jump beyond 8 m snaps, the
  /// rest is lerped.
  void setNetPose(Vector3 pos) {
    if (_netTarget == null || (position - pos).length > 8.0) position = pos.clone();
    _netTarget = pos.clone();
  }

  /// Replica: how far the drawn body sits from the host's latest pose (probe).
  double netPoseDelta() {
    final t = _netTarget;
    return t == null ? 0.0 : (position - t).length;
  }

  void setupDrop(VoxelWorld w, String id, int n, Player player, [double delay = 0.6]) {
    setup(w, 0.15, 0.3);
    itemId = id;
    count = n;
    _player = player;
    _pickupDelay = delay;
    _visual.add(dropModel(id));
    _visual.position = Vector3(0, hover, 0);
    node.add(_visual);
  }

  /// How high a drop's model floats, at its middle.
  static const double hover = 0.25;

  /// How big a drop is, along its longest side: a lump (a block, an apple)
  /// lies small; a long thing (a tool, a torch, a flower) keeps enough length
  /// to be read.
  static const double blockSize = 0.28, itemSize = 0.40;

  /// The item's own model (the one the hand holds and the icon shows),
  /// shrunk to a drop's size and centred on the node it spins about.
  static Node dropModel(String id) {
    final shape = VoxelMeshBuilder.itemShape(id);
    final k = dropScale(shape);
    return VoxelMeshBuilder.heldItem(id)
      ..scale = Vector3.all(k)
      ..position = -shape.bounds().center * k;
  }

  /// How much [shape] is scaled to lie on the ground.
  static double dropScale(ItemShape shape) {
    final b = shape.bounds();
    final extent = b.max - b.min;
    final longest = math.max(extent.x, math.max(extent.y, extent.z));
    final long = shape.flat || extent.y > 1.5 * math.max(extent.x, extent.z);
    return (long ? itemSize : blockSize) / longest;
  }

  /// The local player or, on the host, a peer's puppet, whichever is nearest
  /// within 3 m. RemotePlayer is reached through [Target] so this file never
  /// names it: ItemDrop -> RemotePlayer -> Player would close an import cycle.
  Target? _nearestBody() {
    Target? best = _player.isDead ? null : _player;
    var bestD = best == null ? double.infinity : (_player.position - position).length;
    if (Net.instance.isHost) {
      for (final b in Net.instance.puppetBodies()) {
        final d = (b.position - position).length;
        if (d < bestD && Net.instance.peerHasRoom(b.peerId, itemId, count, bonus)) {
          bestD = d;
          best = b;
        }
      }
    }
    return bestD < 3.0 ? best : null;
  }

  void update(double dt) {
    if (replica) {
      _age += dt;
      final t = _netTarget;
      if (t != null) position = position + (t - position) * (dt * 12.0).clamp(0.0, 1.0);
      syncNode();
      _visual.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), _age * 2.0);
      _visual.position = Vector3(0, hover + math.sin(_age * 3.0) * 0.06, 0);
      return;
    }
    // Stage 24: a restored drop waits for its chunk (unloaded reads as air).
    if (!world.isLoaded(IVec3.floor(position))) return;
    _age += dt;
    if (_age > 300.0) {
      removed = true;
      return;
    }
    applyGravity(dt);
    velocity.x = lerpd(velocity.x, 0.0, dt * 4.0);
    velocity.z = lerpd(velocity.z, 0.0, dt * 4.0);
    if (!replica && _age > _pickupDelay) {
      final body = _nearestBody();
      if (body != null) {
        final toPlayer = (body.position + Vector3(0, 0.9, 0)) - centre();
        final d = toPlayer.length;
        if (d < 1.0) {
          _pickUpBy(body);
          return;
        }
        if (d < 3.0) {
          velocity += toPlayer.normalized() * dt * 40.0;
          if (velocity.length > 9.0) velocity = velocity.normalized() * 9.0;
        }
      }
    }
    move(dt);
    syncNode();
    _visual.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), _age * 2.0);
    _visual.position = Vector3(0, hover + math.sin(_age * 3.0) * 0.06, 0);
  }

  /// Stage 24: what the save keeps of a drop.
  Map<String, Object> toJson() => {
        'item': itemId,
        'count': count,
        'bonus': bonus,
        'pos': [position.x, position.y, position.z],
      };

  void _pickUpBy(Target body) {
    if (identical(body, _player)) {
      _pickUp();
      return;
    }
    // A puppet: the peer's own inventory takes it; what does not fit comes
    // back as `give_rest` (stage 25).
    Net.instance.givePeer(body.peerId, itemId, count, bonus);
    removed = true;
  }

  void _pickUp() {
    if (bonus > 0) {
      if (_player.inventory.addStack(ItemStack(itemId, 1, bonus: bonus))) {
        _player.notify('+ ${Hud.itemLabel(itemId, bonus)}');
        Sfx.play('pickup', -8.0);
        removed = true;
      }
      return;
    }
    final left = _player.pickUp(itemId, count);
    if (left <= 0) {
      removed = true;
    } else {
      count = left;
      _age = 0.0;
      _pickupDelay = 2.0;
    }
  }

  static bool isBlockDrop(String id) => Items.isBlock(id) && Blocks.has(id);
}
