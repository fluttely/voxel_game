import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

/// voxel_core's [VoxelBody] with a scene node that carries its visuals. A
/// fixed step moves the body and sets the node's pose ([syncNode]); a frame
/// draws the node between the poses of the last two steps ([drawNode]), so the
/// body moves as evenly as the display runs, whatever the step's rate.
///
/// Whoever runs the steps calls [beginStep] before each and [drawNode] once a
/// frame. A body that is only ever synced stands at its last pose.
class NodeBody extends VoxelBody {
  /// The node the body's model hangs under; add it to the scene.
  final Node node = Node();

  /// Gone from the world; whoever owns the body drops it at the end of the
  /// frame.
  bool removed = false;

  final Vector3 _from = Vector3.zero(), _to = Vector3.zero(), _drawn = Vector3.zero();
  double _yawFrom = 0.0, _yawTo = 0.0, _pitchFrom = 0.0, _pitchTo = 0.0;
  bool _synced = false;
  bool _drawnStill = false;

  /// Where the node stands this frame: the last pose it was drawn or synced at.
  Vector3 get drawnPosition => _drawn;

  /// Sets the node's pose at the end of this step and puts the node there: at
  /// [position], or [at], turned by [yaw] about the vertical and then by
  /// [pitch] (radians; a turn left out keeps its value). A body's first sync,
  /// and one with [snap] (a respawn, a placement), is also the pose the frames
  /// draw from, so the node jumps there instead of gliding from where it was.
  void syncNode({Vector3? at, double? yaw, double? pitch, bool snap = false}) {
    _to.setFrom(at ?? position);
    if (yaw != null) _yawTo = yaw;
    if (pitch != null) _pitchTo = pitch;
    if (snap || !_synced) {
      _from.setFrom(_to);
      _yawFrom = _yawTo;
      _pitchFrom = _pitchTo;
    }
    _synced = true;
    _write(_to, _yawTo, _pitchTo);
    _drawnStill = _still;
  }

  /// Starts a step: the pose the last one set becomes the one the frames
  /// draw from, until this step sets the next.
  void beginStep() {
    _from.setFrom(_to);
    _yawFrom = _yawTo;
    _pitchFrom = _pitchTo;
  }

  /// Draws the node [alpha] (0..1) of the way from the pose before the last
  /// step's to the last step's: once a frame, with the loop's `alpha`. A body
  /// whose two poses are the same is drawn once and then left alone.
  void drawNode(double alpha) {
    if (_drawnStill) return;
    final still = _still;
    final t = still ? 1.0 : alpha;
    _drawn
      ..setFrom(_to)
      ..sub(_from)
      ..scale(t)
      ..add(_from);
    _write(_drawn, lerpAngle(_yawFrom, _yawTo, t), lerpd(_pitchFrom, _pitchTo, t));
    _drawnStill = still;
  }

  bool get _still => _from == _to && _yawFrom == _yawTo && _pitchFrom == _pitchTo;

  void _write(Vector3 at, double yaw, double pitch) {
    if (!identical(at, _drawn)) _drawn.setFrom(at);
    final turn = yaw == 0.0 && pitch == 0.0 ? Quaternion.identity() : eulerYXZ(pitch, yaw, 0.0);
    node.mutateLocalTransform((m) => m.setFromTranslationRotation(at, turn));
  }
}
