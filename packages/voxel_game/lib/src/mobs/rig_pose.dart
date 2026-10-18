/// A pose a rig holds over its walk, declared: target angles for some of its
/// named parts (`body`, `head`, `arm0`, `arm1`, `leg0`, `leg1`..) and a lean
/// of the whole body, blended in and out at [rate]. A player's are
/// `PlayerSpec.poses`, held by `PlayerEntity.holdPose`: a dash, a cheer, a
/// bow.
class RigPose {
  /// A pose of [parts], leaning [lean] radians, blended at [rate].
  const RigPose({this.parts = const {}, this.lean = 0.0, this.rate = 20.0}) : assert(rate > 0.0);

  /// Each posed part's angles (applied Y, X, Z, as `RigPart`'s), radians: at
  /// full weight they replace what the walk, the seat and the glide gave it.
  final Map<String, ({double rx, double ry, double rz})> parts;

  /// How far the whole model tilts about X at full weight, radians: negative
  /// leans forward.
  final double lean;

  /// How fast the pose blends in and out: the weight goes `rate × dt` of the
  /// way there each frame.
  final double rate;
}
