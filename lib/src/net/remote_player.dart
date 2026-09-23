import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../entities/target.dart';
import '../mobs/rig.dart';

/// Another player in a networked game: a body standing where its peer says,
/// drawn with the player's rig. On the host it is a [Target] the mobs hunt;
/// the damage it takes goes to its peer through [onHurt].
class RemotePlayer extends GameEntity implements Target {
  /// Peer [peer]'s player.
  RemotePlayer(this.peer, Vector3 at) {
    position = at.clone();
    _to = at.clone();
    halfWidth = 0.3;
    height = 1.75;
  }

  /// The peer's number.
  final int peer;

  /// Where damage dealt to it goes (the host sends it to the peer).
  void Function(Damage damage)? onHurt;

  /// The model; null headless.
  RigInstance? rig;

  Vector3 _to = Vector3.zero();
  double _yaw = 0.0;
  double _speed = 0.0;
  bool _dead = false;

  @override
  bool get isDead => _dead;

  /// The yaw its peer faces.
  double get yaw => _yaw;

  /// Where the peer says its player is, looking where, alive or not.
  void setPose(Vector3 at, double yaw, {bool dead = false}) {
    _to = at.clone();
    _yaw = yaw;
    _dead = dead;
  }

  @override
  void attached(VoxelGame game) {
    setup(game.world, 0.3, 1.75);
    if (game.headless) return;
    final r = game.spec.player.rig.build(0.3, 1.75);
    rig = r;
    node.add(r.root);
  }

  @override
  void tick(VoxelGame game, double dt) {
    final before = position.clone();
    position = position + (_to - position) * math.min(1.0, dt * 12.0);
    final moved = position - before
      ..y = 0;
    _speed = lerpd(_speed, moved.length / math.max(dt, 1e-6), math.min(1.0, dt * 8.0));
    syncNode();
    final r = rig;
    if (r == null) return;
    r.root.visible = !_dead;
    r.animate(dt, speed: _speed, targetYaw: _yaw, onFloor: true);
    r.place(Vector3.zero());
  }

  @override
  double takeDamage(Damage damage) {
    if (_dead) return 0.0;
    onHurt?.call(damage);
    return damage.amount;
  }
}
