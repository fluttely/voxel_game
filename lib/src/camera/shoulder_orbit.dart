import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

/// The third-person eye: behind the head, over a shoulder and a little above,
/// pulled in by walls. Shoulder and rise grow with the distance, so the whole
/// segment from the head to the eye is a straight line that can be swept, and
/// an eye pulled all the way in ends on the head itself, never beside it.
class ShoulderOrbit {
  /// An orbit [distance] behind the head, [shoulder] to its right and [rise]
  /// above, when nothing is in the way.
  ShoulderOrbit({this.distance = 4.8, this.shoulder = 0.55, this.rise = 0.15}) : current = distance;

  /// How far behind the eye sits, unobstructed.
  final double distance;

  /// How far right of the head, at full distance.
  final double shoulder;

  /// How far above, at full distance.
  final double rise;

  /// Half the box the eye is treated as: the near plane is a rectangle in
  /// front of the eye, so the eye is not a point.
  static const double eyeRadius = 0.25;

  /// How far down the orbit the eye sits now.
  double current;

  /// The eye's offset from the pivot at orbit distance [dist].
  Vector3 offset(Vector3 right, Vector3 up, Vector3 back, double dist) {
    final t = dist / distance;
    return right * (shoulder * t) + up * (rise * t) + back * dist;
  }

  /// How far down the orbit the eye may sit: the box of the eye swept from
  /// [pivot] along the orbit, [jitter] (a jolt, a sway) included because it
  /// moves the eye too, stopped at the last clear step.
  double clearFrom(
          {required Vector3 pivot,
          required Vector3 right,
          required Vector3 up,
          required Vector3 back,
          required Vector3 jitter,
          required bool Function(int x, int y, int z) cellIsClear}) =>
      clearDistance(distance, (d) => pivot + offset(right, up, back, d) + jitter, cellIsClear);

  /// Moves [current] toward [clearFrom] for this frame. In at once, out
  /// gently: an eye eased into place is an eye inside the wall for the length
  /// of the ease.
  double settle(double dt,
      {required Vector3 pivot,
      required Vector3 right,
      required Vector3 up,
      required Vector3 back,
      required Vector3 jitter,
      required bool Function(int x, int y, int z) cellIsClear}) {
    final clear = clearFrom(pivot: pivot, right: right, up: up, back: back, jitter: jitter, cellIsClear: cellIsClear);
    current = clear < current ? clear : lerpd(current, clear, math.min(1.0, dt * 6.0));
    return current;
  }

  /// The furthest a box of [eyeRadius] slides along [eyeAt] from 0 to
  /// [wanted] with every cell it touches accepted by [cellIsClear], marched
  /// outward: an air pocket behind a wall is not room.
  static double clearDistance(double wanted, Vector3 Function(double distance) eyeAt, bool Function(int x, int y, int z) cellIsClear) {
    const step = eyeRadius * 0.5;
    var clear = 0.0;
    while (clear < wanted) {
      final next = math.min(clear + step, wanted);
      if (!boxIsClear(eyeAt(next), eyeRadius, cellIsClear)) return clear;
      clear = next;
    }
    return wanted;
  }

  /// Whether every cell a box of half-size [radius] at [at] touches is clear.
  static bool boxIsClear(Vector3 at, double radius, bool Function(int x, int y, int z) cellIsClear) {
    for (var y = (at.y - radius).floor(); y <= (at.y + radius).floor(); y++) {
      for (var z = (at.z - radius).floor(); z <= (at.z + radius).floor(); z++) {
        for (var x = (at.x - radius).floor(); x <= (at.x + radius).floor(); x++) {
          if (!cellIsClear(x, y, z)) return false;
        }
      }
    }
    return true;
  }
}
