import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The rotation of Euler angles applied Y, then X, then Z (yaw, pitch, roll):
/// the order an animated part is posed in.
Quaternion eulerYXZ(double x, double y, double z) {
  final qy = Quaternion.axisAngle(Vector3(0, 1, 0), y);
  final qx = Quaternion.axisAngle(Vector3(1, 0, 0), x);
  final qz = Quaternion.axisAngle(Vector3(0, 0, 1), z);
  return qy * qx * qz;
}

/// [from] moved toward [to] by [t] along the shorter way round the circle, in
/// radians.
double lerpAngle(double from, double to, double t) {
  var d = (to - from) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  if (d < -math.pi) d += 2 * math.pi;
  return from + d * t;
}

/// [a] moved toward [b] by [t].
double lerpd(double a, double b, double t) => a + (b - a) * t;
