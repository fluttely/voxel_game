import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

/// One posable piece of a creature's rig: a pivot node at a rest position,
/// posed every frame by Euler angles (applied Y, X, Z), a per-axis scale and
/// an offset from the rest position. Set the fields, then [apply].
class RigPart {
  /// A part pivoting on [node], resting at [base] in its parent's space.
  RigPart(this.node, this.base) {
    node.position = base.clone();
  }

  /// The pivot; the part's meshes hang under it.
  final Node node;

  /// The rest position of the pivot.
  final Vector3 base;

  /// Rotation about x (pitch), in radians.
  double rx = 0;

  /// Rotation about y (yaw), in radians.
  double ry = 0;

  /// Rotation about z (roll), in radians.
  double rz = 0;

  /// Scale along x.
  double sx = 1;

  /// Scale along y.
  double sy = 1;

  /// Scale along z.
  double sz = 1;

  /// Offset from [base] along x, in metres.
  double offX = 0;

  /// Offset from [base] along y, in metres.
  double offY = 0;

  /// Offset from [base] along z, in metres.
  double offZ = 0;

  /// Writes the pose into [node]'s matrix at once. Every creature poses every
  /// part every step, so this allocates nothing: the node's own setters
  /// rebuild its matrix once for each of rotation and scale, and the pose's
  /// quaternion and vectors were new objects each time.
  void apply() {
    eulerYXZInto(_rotation, rx, ry, rz);
    _translation.setValues(base.x + offX, base.y + offY, base.z + offZ);
    _scale.setValues(sx, sy, sz);
    node.mutateLocalTransform(_compose);
  }

  // The pose [apply] composes, shared by every part: the node copies it into
  // its matrix before [apply] returns.
  static final Vector3 _translation = Vector3.zero(), _scale = Vector3.zero();
  static final Quaternion _rotation = Quaternion.identity();
  static void _compose(Matrix4 m) => m.setFromTranslationRotationScale(_translation, _rotation, _scale);
}
