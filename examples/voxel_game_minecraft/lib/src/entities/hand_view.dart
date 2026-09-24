import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import 'voxel_mesh_builder.dart';
import 'package:voxel_scene/voxel_scene.dart';

/// The first-person hand: the player's right forearm and whatever it is
/// holding, drawn a little over half a metre in front of the eye.
///
/// Minecraft's first person is not a bare camera — the largest thing moving on
/// screen is this hand. The eye itself barely dips; the arm answers every
/// footfall with a wide, lagging sway and throws the item across the corner of
/// the screen on every swing, and that is what makes walking read as walking.
/// Bobbing the eye hard enough to carry that on its own is what gives people
/// motion sickness, so the eye stays calm and the hand does the work.
///
/// It lives in world space rather than in a separate view pass this renderer
/// does not have: every frame [update] rebuilds the node's transform from the
/// camera's own basis, so the arm sits still relative to the screen whatever
/// the player is looking at.
class HandView {
  static const double s = 0.055; // metres per voxel, the player model's scale

  /// How far in front of the eye the fist sits. Far enough to clear the 0.05 m
  /// near plane by a wide margin, close enough that the arm fills the corner.
  static const double reach = 0.72;

  /// Minecraft's six ticks: how long one swing takes.
  static const double swingSeconds = 0.3;

  final Node root = Node(name: 'HandView');
  final Node _arm = Node(); // the forearm, angled off toward the bottom corner
  final Node _wrist = Node(); // what the fist holds, upright in view space
  Node? _held;
  String _heldId = '';
  double _swing = 0.0; // 1 at the start of a swing, down to 0
  double _phase = 0.0; // the walk cycle this hand answers, lagging the eye's
  double _weight = 0.0; // how much of the sway is in

  /// How a tool sits in the fist: standing up out of it and leaning into the
  /// screen, its head in the upper part of the corner where it can be seen.
  /// It takes the third-person model's quarter turn about its shaft first, so
  /// a pickaxe's points run into the screen and back, along the chop, instead
  /// of across it.
  static final Quaternion toolPose = eulerYXZ(-0.62, 0.0, 0.26) * VoxelMeshBuilder.headInSwingPlane;

  /// What the fist holds right now, for the probes.
  Node? get heldNode => _held;

  bool get visible => root.visible;
  set visible(bool v) => root.visible = v;

  /// Builds the forearm in the player's own colours. Local space here is the
  /// camera's: +X right, +Y up, -Z into the screen.
  void build(Vector3 skin, Vector3 shirt) {
    root.removeAll();
    _arm.removeAll();
    _wrist.removeAll();
    _held = null;
    _heldId = '';
    final cloth = shirt + (Vector3(0.52, 0.48, 0.44) - shirt) * 0.2;
    final trim = cloth * 0.7;
    final v = <IVec3, Vector3>{};
    // A 4x4 bar running +Z, which is backward, out of the screen: the fist is
    // at the origin and the elbow runs away behind the near plane, exactly as
    // an arm held in front of you leaves the eye.
    VoxelModel.box(v, const IVec3(-2, -2, 0), const IVec3(1, 1, 3), skin, 0.02);
    VoxelModel.box(v, const IVec3(-2, -2, 4), const IVec3(1, 1, 4), trim, 0.03);
    VoxelModel.box(v, const IVec3(-2, -2, 5), const IVec3(1, 1, 14), cloth, 0.03);
    _arm.add(VoxelModelMesh.node(v, s));
    // Down and out, so the elbow leaves the frame at the bottom right corner
    // instead of standing in the middle of the view like a post.
    _arm.rotation = eulerYXZ(0.72, 0.62, 0.0);
    root.add(_arm);
    root.add(_wrist);
  }

  /// Puts [itemId] in the fist (the empty string empties it).
  void setHeld(String itemId) {
    if (itemId == _heldId) return;
    _heldId = itemId;
    final old = _held;
    if (old != null) {
      _wrist.remove(old);
      _held = null;
    }
    if (itemId == '') return;
    final held = VoxelMeshBuilder.heldItem(itemId);
    if (VoxelMeshBuilder.itemShape(itemId).block) {
      // A block is shown turned off-square, so two of its faces catch the
      // light and it reads as a cube rather than as a painted square.
      held.rotation = eulerYXZ(-0.25, 0.7, 0.0);
      held.position = Vector3(0.0, 0.02, 0.0);
      held.scale = Vector3(0.58, 0.58, 0.58);
    } else {
      held.rotation = toolPose;
      held.scale = Vector3(0.6, 0.6, 0.6);
    }
    _wrist.add(held);
    _held = held;
  }

  /// Starts a swing (the same call the player model's arm answers).
  void swing() => _swing = 1.0;

  /// Places the hand for this frame.
  ///
  /// [eye], [right], [up] and [forward] are the camera's own, so the hand
  /// inherits the eye's bob and roll and then adds its own on top; [phase] is
  /// the walk cycle and [weight] how much of it is in.
  void update({
    required double dt,
    required Vector3 eye,
    required Vector3 right,
    required Vector3 up,
    required Vector3 forward,
    required double phase,
    required double weight,
  }) {
    if (_swing > 0.0) _swing = math.max(_swing - dt / swingSeconds, 0.0);
    // The arm lags the eye by about a fifth of a step. In Minecraft the hand is
    // bobbed by the same walk phase as the view but is not pinned to it, and
    // the little slip between them is most of what you actually see moving.
    _phase = phase - 0.6;
    _weight = weight;
    final sin = math.sin(_phase);
    final cos = math.cos(_phase);
    // The hand's own sway, five times the eye's and mostly sideways: it is a
    // hand on the end of an arm, not a head on a neck.
    var x = sin * 0.045 * _weight;
    var y = -cos.abs() * 0.035 * _weight;
    var z = 0.0;
    var chop = 0.0;
    var turn = 0.0;
    if (_swing > 0.0) {
      // Minecraft's swing: the item dives toward the middle of the screen and
      // down, rolls over, and comes back. A sine of the square root front-loads
      // it, so the strike is fast and the return is lazy.
      final t = 1.0 - _swing;
      final fast = math.sin(math.sqrt(t) * math.pi);
      x -= 0.16 * fast;
      y += 0.05 * math.sin(math.sqrt(t) * math.pi * 2.0);
      z -= 0.10 * math.sin(t * math.pi);
      chop = -0.62 * fast;
      turn = 0.25 * fast;
    }
    final offset = right * (0.44 + x) + up * (-0.38 + y) + forward * (reach + z);
    root.localTransform = Matrix4.columns(
      Vector4(right.x, right.y, right.z, 0.0),
      Vector4(up.x, up.y, up.z, 0.0),
      Vector4(-forward.x, -forward.y, -forward.z, 0.0),
      Vector4(eye.x + offset.x, eye.y + offset.y, eye.z + offset.z, 1.0),
    );
    // The swing turns the whole fist: the arm and what it holds move together.
    _arm.rotation = eulerYXZ(0.72 + chop * 0.30, 0.62 + turn, 0.0);
    _wrist.rotation = eulerYXZ(chop, turn, 0.0);
  }
}
