import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../player/player_spec.dart';

/// What the first person sees of the player: the arm in the corner of the
/// screen holding the item in hand, swinging when it mines, hits or places;
/// and the crack darkening the block being mined.
///
/// The hand is a world-space node set against the camera's basis every frame
/// (flutter_scene has no view-space pass), so it follows the look exactly.
class FirstPersonView {
  /// The view of [game]; its nodes are added to the scene.
  FirstPersonView(this.game) {
    final skin = game.player.spec.rig;
    final arm = <IVec3, Vector3>{};
    VoxelModel.box(arm, const IVec3(-2, -2, -12), const IVec3(1, 1, -1), _rgb(skin.skinColor), 0.03);
    _hand.add(VoxelModelMesh.node(arm, 0.055)..castsShadows = false);
    _hand.add(_held);
    game.scene!.add(_hand);
    // The crack is drawn from opaque sticks, as the outline is: a blended
    // darkening box never reaches the screen in flutter_scene 0.23. Each stage
    // adds its own jagged segments on all six faces.
    final mat = UnlitMaterial()
      ..baseColorFactor = Vector4(0.10, 0.09, 0.08, 1)
      ..vertexColorWeight = 0.0
      ..depthBias = 0.02;
    for (var stage = 0; stage < _crackSegments.length; stage++) {
      final group = Node()..visible = false;
      for (var axis = 0; axis < 3; axis++) {
        for (final side in const [0.0, 1.0]) {
          final a1 = (axis + 1) % 3, a2 = (axis + 2) % 3;
          for (final (alongU, u, v, len) in _crackSegments[stage]) {
            final size = Vector3.all(0.0);
            size[axis] = 0.012;
            size[alongU ? a1 : a2] = len;
            size[alongU ? a2 : a1] = 0.045;
            final at = Vector3.zero();
            at[axis] = side == 0.0 ? -0.004 : 1.004;
            at[a1] = alongU ? u + len / 2 : u;
            at[a2] = alongU ? v : v + len / 2;
            group.add(MirroredCamera.primitiveNode(Mesh(CuboidGeometry(size), mat), castsShadows: false)..position = at);
          }
        }
      }
      _cracks.add(group);
      game.scene!.add(group);
    }
  }

  /// The game shown.
  final VoxelGame game;

  final Node _hand = Node()..castsShadows = false;
  final Node _held = Node()..castsShadows = false;
  final List<Node> _cracks = [];

  /// Per stage, the segments it adds on each face: along the face's first
  /// axis or its second, from (u, v), this long (face coordinates 0..1).
  static const List<List<(bool, double, double, double)>> _crackSegments = [
    [(true, 0.30, 0.50, 0.25), (false, 0.55, 0.50, 0.20)],
    [(true, 0.55, 0.70, 0.25), (false, 0.30, 0.20, 0.30)],
    [(true, 0.10, 0.20, 0.20), (false, 0.80, 0.55, 0.30), (true, 0.55, 0.30, 0.30)],
    [(false, 0.15, 0.55, 0.35), (true, 0.35, 0.85, 0.30), (false, 0.62, 0.05, 0.25)],
  ];
  final Map<String, Node> _models = {};
  String _heldId = '';
  double _swing = 0.0;

  static Vector3 _rgb(int c) => Vector3(((c >> 16) & 0xFF) / 255.0, ((c >> 8) & 0xFF) / 255.0, (c & 0xFF) / 255.0);

  /// Starts a swing of the hand.
  void swing() => _swing = 1.0;

  Node _model(String id) => _models.putIfAbsent(id, () {
        final t = game.items[id];
        final c = Vector3(t.r, t.g, t.b);
        final v = <IVec3, Vector3>{};
        final Vector3 origin;
        if (t.block != null) {
          VoxelModel.box(v, IVec3.zero, const IVec3(7, 7, 7), c, 0.05);
          origin = Vector3(4, 0, 4);
        } else {
          // A handle and a head: reads as a tool, a weapon or a stick.
          VoxelModel.box(v, IVec3.zero, const IVec3(0, 9, 0), Vector3(0.45, 0.32, 0.18), 0.03);
          if (t.tool != null) {
            VoxelModel.box(v, const IVec3(-2, 9, 0), const IVec3(2, 11, 0), c);
          } else {
            VoxelModel.box(v, const IVec3(-1, 0, -1), const IVec3(1, 3, 1), c);
          }
          origin = Vector3(0.5, 0, 0.5);
        }
        return VoxelModelMesh.node(v, t.block != null ? 0.03 : 0.035, origin)..castsShadows = false;
      });

  /// Places the hand and the crack for this frame.
  void update(double dt) {
    final p = game.player;
    final first = p.cameraMode == CameraMode.firstPerson && !p.isDead;
    _hand.visible = first;
    _updateCrack();
    if (!first) return;
    final id = p.heldItem;
    if (id != _heldId) {
      for (final c in List.of(_held.children)) {
        _held.remove(c);
      }
      if (id.isNotEmpty) _held.add(_model(id));
      _heldId = id;
    }
    _swing = math.max(_swing - dt / 0.3, 0.0);
    final yaw = p.yaw;
    final fwd = p.forward;
    final right = Vector3(math.cos(yaw), 0, -math.sin(yaw));
    final up = right.cross(fwd).normalized();
    final s = math.sin((1.0 - _swing) * math.pi) * (_swing > 0 ? 1.0 : 0.0);
    final eye = p.eyePosition;
    _hand.position = eye + right * (0.36 - s * 0.12) - up * (0.30 + s * 0.05) + fwd * (0.45 + s * 0.15);
    final basis = Matrix3.columns(right, up, -fwd);
    _hand.rotation = Quaternion.fromRotation(basis) * Quaternion.axisAngle(Vector3(1, 0, 0), 0.35 - s * 1.1);
    _held
      ..position = Vector3(0, 0.03, -0.62)
      ..rotation = Quaternion.axisAngle(Vector3(1, 0, 0), -1.2);
  }

  void _updateCrack() {
    final p = game.player;
    final hit = p.aimedBlock;
    final stage = p.mineProgress <= 0.0 || hit == null ? -1 : (p.mineProgress * 4.0).toInt().clamp(0, 3);
    for (var i = 0; i < _cracks.length; i++) {
      _cracks[i].visible = i <= stage;
      if (hit != null && i <= stage) _cracks[i].position = Vector3(hit.block.x.toDouble(), hit.block.y.toDouble(), hit.block.z.toDouble());
    }
  }
}
