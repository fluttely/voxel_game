import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' hide Spawner;
import 'package:vector_math/vector_math.dart';

import 'package:voxel_engine/core.dart';
import '../game/sfx.dart';
import '../player/player.dart';
import 'package:voxel_scene/voxel_scene.dart';
import '../world/voxel_world.dart';

/// A fishing bobber: flies from the rod hand to the water cell it was cast at,
/// floats there, and after a random wait dips for a short bite window. The line
/// is a thin box stretched from the player's hand to the bobber every frame,
/// because a line geometry here is built once and cannot be rewritten cheaply.
/// Stage 25: a [replica] is another peer's bobber, drawn at the pose that peer
/// streams with the line from its puppet's hand.
class Bobber {
  Bobber(this.world, Player this.player, Vector3 from, IVec3 cell)
      : replica = false,
        _handOf = player.model.handWorldPosition {
    _start = from.clone();
    position = from.clone();
    target = cell.toVector3() + Vector3(0.5, 0.85, 0.5);
    _wait = 3.0 + player!.main.random.nextDouble() * 5.0;
    _buildBody();
  }

  /// Another peer's bobber: no flight, no bites; it follows [setNetPose] and
  /// hangs from [hand] (its puppet's).
  Bobber.replica(this.world, Vector3 Function() hand, Vector3 pos)
      : player = null,
        replica = true,
        _handOf = hand {
    landed = true;
    _start = pos.clone();
    position = pos.clone();
    target = pos.clone();
    _netTarget = pos.clone();
    _buildBody();
  }

  void _buildBody() {
    final float = MirroredCamera.primitiveNode(
      Mesh(SphereGeometry(radius: 0.11), UnlitMaterial()..baseColorFactor = Vector4(0.90, 0.20, 0.15, 1)),
    );
    final cap = MirroredCamera.primitiveNode(
      Mesh(SphereGeometry(radius: 0.06), UnlitMaterial()..baseColorFactor = Vector4(0.95, 0.95, 0.92, 1)),
    )..position = Vector3(0, 0.12, 0);
    node.add(float);
    node.add(cap);
    _line = MirroredCamera.primitiveNode(
      Mesh(CuboidGeometry(Vector3(0.012, 0.012, 1.0)), UnlitMaterial()..baseColorFactor = Vector4(0.12, 0.12, 0.12, 1)),
      castsShadows: false,
    );
    node.position = position;
  }

  static const double biteWindow = 1.5;

  final VoxelWorld world;

  /// The caster; null on a replica.
  final Player? player;
  final bool replica;
  final Vector3 Function() _handOf;
  final Node node = Node(name: 'Bobber');
  late final Node _line;
  Vector3 position = Vector3.zero();
  late final Vector3 target;
  bool landed = false;
  double biteLeft = 0.0;
  bool removed = false;
  late final Vector3 _start;
  Vector3 _netTarget = Vector3.zero();
  double _flight = 0.0;
  double _wait = 5.0;
  double _phase = 0.0;

  /// The line lives beside the bobber, not under it, so it is not dragged by
  /// the bobber's own bobbing.
  Node get lineNode => _line;

  bool get isBiting => biteLeft > 0.0;

  /// The fish tugs: the bobber dips, a splash, and the player has [biteWindow]
  /// seconds to react.
  void bite() {
    final p = player!;
    biteLeft = biteWindow;
    _wait = 3.0 + p.main.random.nextDouble() * 5.0;
    Sfx.play('splash', -6.0);
    p.notify('Something bites!');
  }

  /// Probe hook: land at once and start a bite this frame.
  void forceBite() {
    landed = true;
    _flight = 1.0;
    position = target.clone();
    bite();
  }

  /// Replica: the peer's latest pose; a jump beyond 8 m snaps.
  void setNetPose(Vector3 pos) {
    if ((position - pos).length > 8.0) position = pos.clone();
    _netTarget = pos.clone();
  }

  void update(double dt) {
    if (replica) {
      position = position + (_netTarget - position) * (dt * 12.0).clamp(0.0, 1.0);
      node.position = position;
      _stretchLine();
      return;
    }
    if (!landed) {
      _flight = math.min(_flight + dt * 2.2, 1.0);
      final p = _start + (target - _start) * _flight;
      p.y += math.sin(_flight * math.pi) * 1.4;
      position = p;
      if (_flight >= 1.0) {
        landed = true;
        Sfx.play('splash', -14.0);
      }
    } else {
      _phase += dt;
      var dip = 0.0;
      if (biteLeft > 0.0) {
        biteLeft -= dt;
        dip = -0.22;
      } else {
        _wait -= dt;
        if (_wait <= 0.0) bite();
      }
      final wanted = target.y + math.sin(_phase * 3.0) * 0.04 + dip;
      position.y = position.y + (wanted - position.y) * (dt * 12.0).clamp(0.0, 1.0);
    }
    node.position = position;
    _stretchLine();
  }

  void _stretchLine() {
    final hand = _handOf();
    final delta = position + Vector3(0, 0.12, 0) - hand;
    final length = delta.length;
    if (length < 1e-4) {
      _line.visible = false;
      return;
    }
    _line.visible = true;
    _line.position = hand + delta * 0.5;
    _line.scale = Vector3(1, 1, length);
    // The unit box points along -Z; aim it down the line.
    final dir = delta / length;
    final axis = Vector3(0, 0, -1).cross(dir);
    final dot = Vector3(0, 0, -1).dot(dir);
    if (axis.length2 < 1e-8) {
      _line.rotation = dot > 0 ? Quaternion.identity() : Quaternion.axisAngle(Vector3(0, 1, 0), math.pi);
    } else {
      _line.rotation = Quaternion.axisAngle(axis.normalized(), math.acos(dot.clamp(-1.0, 1.0)));
    }
  }
}
