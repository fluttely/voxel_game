import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The rotation of Euler angles applied Y, then X, then Z (yaw, pitch, roll):
/// the order an animated part is posed in.
Quaternion eulerYXZ(double x, double y, double z) => eulerYXZInto(Quaternion.identity(), x, y, z);

/// [eulerYXZ] written into [out], which it returns: the product of the three
/// axis rotations worked out by hand, so posing a part every step allocates
/// nothing.
Quaternion eulerYXZInto(Quaternion out, double x, double y, double z) {
  final sx = math.sin(x * 0.5), cx = math.cos(x * 0.5);
  final sy = math.sin(y * 0.5), cy = math.cos(y * 0.5);
  final sz = math.sin(z * 0.5), cz = math.cos(z * 0.5);
  // qy * qx, then that times qz.
  final ax = cy * sx, ay = sy * cx, az = -sy * sx, aw = cy * cx;
  return out..setValues(ax * cz + ay * sz, ay * cz - ax * sz, aw * sz + az * cz, aw * cz - az * sz);
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
