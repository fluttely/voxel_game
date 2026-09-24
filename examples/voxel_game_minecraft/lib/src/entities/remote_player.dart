import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../game/net.dart';
import 'mob.dart';
import '../player/player.dart';
import 'player_model.dart';
import 'target.dart';
import 'package:voxel_engine/core.dart';

/// Another peer's body: a PlayerModel moved by the poses that peer sends. No
/// physics here.
class RemotePlayer implements Target {
  final Node node = Node(name: 'RemotePlayer');
  final PlayerModel model = PlayerModel();
  @override
  Vector3 position = Vector3.zero();
  Vector3 _target = Vector3.zero();
  double _yaw = 0.0;
  String title = '';
  @override
  int peerId = 0;

  /// Stage 21b: the horse this peer rides (the host's own Mob, or a mob puppet
  /// on a client).
  Mob? mountedOn;
  @override
  bool isDead = false;
  bool removed = false;

  /// Stage 29: the dimension the peer is in (from its pose). A puppet in another
  /// dimension than this world's is hidden: everyone in one dimension sees each
  /// other, nobody sees across.
  int dimension = 0;

  void setupPuppet(String cls, String label) {
    final c = Player.classes[cls] ?? Player.classes['warrior']!;
    model.build(Vector3(0.87, 0.70, 0.55), c.shirt, Vector3(0.25, 0.30, 0.55), Vector3(0.25, 0.16, 0.10));
    node.add(model.root);
    title = label;
    _target = position.clone();
  }

  @override
  Vector3 centre() => position + Vector3(0, 0.9, 0);

  @override
  void takeDamage(double amount, String source, [Vector3? from]) {
    // The host decided the hit; the peer's own Player applies armour and shows the number.
    Net.instance.hurtPeer(peerId, amount, source, from);
  }

  /// The host decided a mob's effect landed; the peer's own player wears it.
  void applyEffect(String id, double seconds) => Net.instance.effectPeer(peerId, id, seconds);

  void setPose(Vector3 pos, double yaw, String held) {
    if ((position - pos).length > 8.0) position = pos.clone();
    _target = pos.clone();
    _yaw = yaw;
    model.setHeld(held);
  }

  void update(double dt) {
    final m = Net.instance.main;
    node.visible = m == null || dimension == m.world.dimension;
    final before = position.clone();
    final h = mountedOn;
    if (h != null && !h.removed) {
      _target = Player.saddlePosition(h);
      _yaw = h.modelYaw();
    }
    position = position + (_target - position) * (dt * 12.0).clamp(0.0, 1.0);
    final speed = (position - before).length / (dt > 0.001 ? dt : 0.001);
    model.yaw = lerpAngle(model.yaw, _yaw, dt * 10.0);
    model.animate(dt, speed, true, false, false);
    node.position = position.clone();
  }
}
