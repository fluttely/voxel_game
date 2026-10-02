import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../mobs/rig.dart';
import '../player/player_spec.dart';

/// What the first person sees of the player: the forearm in the corner of the
/// screen holding the item in hand ([VoxelGame.itemModel], the one drawn
/// everywhere else), swinging when it mines, hits or places; and the crack
/// darkening the block being mined.
///
/// The eye barely dips on a step ([ViewBob]); the hand answers every footfall
/// with a wider, lagging sway and throws the item across the corner of the
/// screen on a swing, and that is what makes walking read as walking without
/// bobbing the eye hard enough to make people ill.
///
/// The hand is a world-space node set against the camera's basis every frame
/// (flutter_scene has no view-space pass), so it follows the look exactly.
class FirstPersonView {
  /// The view of [game]; its nodes are added to the scene.
  FirstPersonView(this.game) {
    final arm = <IVec3, Vector3>{};
    // A 4x4 bar running +Z, out of the screen: the fist is at the origin and
    // the elbow runs away behind the near plane, as an arm held in front of
    // the eye leaves it.
    VoxelModel.box(arm, const IVec3(-2, -2, 0), const IVec3(1, 1, 14), _rgb(game.player.spec.rig.skinColor), 0.03);
    _arm.add(VoxelModelMesh.node(arm, 0.055)..castsShadows = false);
    _hand
      ..add(_arm)
      ..add(_wrist);
    game.scene!.add(_hand);
    // The crack is drawn from opaque sticks, as the outline is: a blended
    // darkening box never reaches the screen in flutter_scene 0.23. A stage's
    // mesh holds its sticks and every earlier stage's, so a crack is one draw.
    final mat = UnlitMaterial()
      ..baseColorFactor = Vector4(0.10, 0.09, 0.08, 1)
      ..vertexColorWeight = 0.0
      ..depthBias = 0.02;
    for (var stage = 0; stage < _crackSegments.length; stage++) {
      _cracks.add(Mesh(BoxMesh.geometry(crackBoxes(stage)), mat));
    }
    game.scene!.add(_crack);
  }

  /// How far in front of the eye the fist sits: well clear of the 0.05 m near
  /// plane, close enough that the arm fills the corner.
  static const double reach = 0.72;

  /// How long one swing takes: Minecraft's six ticks.
  static const double swingSeconds = 0.3;

  /// How a flat or upright item sits in the fist: standing out of it and
  /// leaning into the screen, its head in the upper part of the corner, turned
  /// as a body's fist turns it ([RigInstance.headInSwingPlane]) so a pickaxe's
  /// points run along the chop.
  static final Quaternion toolPose = eulerYXZ(-0.62, 0.0, 0.26) * RigInstance.headInSwingPlane;

  /// How a block sits in the fist: turned off square, so two of its faces
  /// catch the light and it reads as a cube.
  static final Quaternion blockPose = eulerYXZ(-0.25, 0.7, 0.0);

  /// The game shown.
  final VoxelGame game;

  final Node _hand = Node()..castsShadows = false;
  final Node _arm = Node()..castsShadows = false;
  final Node _wrist = Node()..castsShadows = false;
  ({ItemModel model, Node node})? _held;
  final Node _crack = Node()
    ..visible = false
    ..castsShadows = false;
  final List<Mesh> _cracks = [];
  int _crackStage = -1;

  /// Per stage, the segments it adds on each face: along the face's first
  /// axis or its second, from (u, v), this long (face coordinates 0..1).
  static const List<List<(bool, double, double, double)>> _crackSegments = [
    [(true, 0.30, 0.50, 0.25), (false, 0.55, 0.50, 0.20)],
    [(true, 0.55, 0.70, 0.25), (false, 0.30, 0.20, 0.30)],
    [(true, 0.10, 0.20, 0.20), (false, 0.80, 0.55, 0.30), (true, 0.55, 0.30, 0.30)],
    [(false, 0.15, 0.55, 0.35), (true, 0.35, 0.85, 0.30), (false, 0.62, 0.05, 0.25)],
  ];

  /// The sticks of the crack at [stage] (0 to 3) in a block's unit cell: the
  /// segments of every stage up to it, on all six faces, a stick a segment.
  static List<Aabb3> crackBoxes(int stage) {
    final out = <Aabb3>[];
    for (var s = 0; s <= stage; s++) {
      for (var axis = 0; axis < 3; axis++) {
        for (final side in const [0.0, 1.0]) {
          final a1 = (axis + 1) % 3, a2 = (axis + 2) % 3;
          for (final (alongU, u, v, len) in _crackSegments[s]) {
            final half = Vector3.zero();
            half[axis] = 0.006;
            half[alongU ? a1 : a2] = len / 2;
            half[alongU ? a2 : a1] = 0.0225;
            final at = Vector3.zero();
            at[axis] = side == 0.0 ? -0.004 : 1.004;
            at[a1] = alongU ? u + len / 2 : u;
            at[a2] = alongU ? v : v + len / 2;
            out.add(Aabb3.centerAndHalfExtents(at, half));
          }
        }
      }
    }
    return out;
  }

  double _swing = 0.0;

  static Vector3 _rgb(int c) => Vector3(((c >> 16) & 0xFF) / 255.0, ((c >> 8) & 0xFF) / 255.0, (c & 0xFF) / 255.0);

  /// Starts a swing of the hand.
  void swing() => _swing = 1.0;

  /// What the fist holds; null for an empty one.
  ItemModel? get held => _held?.model;

  void _hold(ItemModel? model) {
    if (identical(model, _held?.model)) return;
    if (_held case (:final node, model: _)) _wrist.remove(node);
    _held = null;
    if (model == null) return;
    final node = ItemMesh.of(model).node()..castsShadows = false;
    if (model.grip == ItemGrip.block) {
      node
        ..rotation = blockPose
        ..position = Vector3(0.0, 0.02, 0.0)
        ..scale = Vector3.all(0.58);
    } else {
      node
        ..rotation = toolPose
        ..scale = Vector3.all(0.6);
    }
    _wrist.add(node);
    _held = (model: model, node: node);
  }

  /// Places the hand and the crack for this frame.
  void update(double dt) {
    final p = game.player;
    final first = p.cameraMode == CameraMode.firstPerson && !p.isDead;
    _hand.visible = first;
    _updateCrack();
    if (!first) return;
    final id = p.heldItem;
    _hold(id.isEmpty ? null : game.itemModel(id));
    _swing = math.max(_swing - dt / swingSeconds, 0.0);
    final bob = game.view.viewBob;
    final yaw = p.yaw;
    final fwd = p.forward;
    final right = Vector3(math.cos(yaw), 0, -math.sin(yaw));
    final up = right.cross(fwd).normalized();
    // The arm lags the eye by about a fifth of a step: the slip between the
    // two is most of what is seen moving.
    final phase = bob.phase - 0.6;
    final weight = bob.weight;
    // Five times the eye's sway and mostly sideways: a hand on the end of an
    // arm, not a head on a neck.
    var x = math.sin(phase) * 0.045 * weight;
    var y = -math.cos(phase).abs() * 0.035 * weight;
    var z = 0.0;
    var chop = 0.0;
    var turn = 0.0;
    if (_swing > 0.0) {
      // The item dives toward the middle of the screen and down, rolls over
      // and comes back; a sine of the square root makes the strike fast and
      // the return lazy.
      final t = 1.0 - _swing;
      final fast = math.sin(math.sqrt(t) * math.pi);
      x -= 0.16 * fast;
      y += 0.05 * math.sin(math.sqrt(t) * math.pi * 2.0);
      z -= 0.10 * math.sin(t * math.pi);
      chop = -0.62 * fast;
      turn = 0.25 * fast;
    }
    final at = p.drawnEye + bob.offset + right * (0.44 + x) + up * (-0.38 + y) + fwd * (reach + z);
    _hand.localTransform = Matrix4.columns(
      Vector4(right.x, right.y, right.z, 0.0),
      Vector4(up.x, up.y, up.z, 0.0),
      Vector4(-fwd.x, -fwd.y, -fwd.z, 0.0),
      Vector4(at.x, at.y, at.z, 1.0),
    );
    // Down and out, so the elbow leaves the frame at the bottom right corner;
    // the swing turns the whole fist, the arm and what it holds together.
    _arm.rotation = eulerYXZ(0.72 + chop * 0.30, 0.62 + turn, 0.0);
    _wrist.rotation = eulerYXZ(chop, turn, 0.0);
  }

  void _updateCrack() {
    final p = game.player;
    final hit = p.aimedBlock;
    final stage = p.mineProgress <= 0.0 || hit == null ? -1 : (p.mineProgress * 4.0).toInt().clamp(0, 3);
    _crack.visible = stage >= 0;
    if (stage < 0) return;
    _crack.position = Vector3(hit!.block.x.toDouble(), hit.block.y.toDouble(), hit.block.z.toDouble());
    if (stage == _crackStage) return;
    _crackStage = stage;
    _crack.mesh = _cracks[stage];
  }
}
