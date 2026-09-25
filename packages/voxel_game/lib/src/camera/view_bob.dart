import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

/// View bobbing: the eye drops by `|cos|` of the walk phase,
/// sways sideways by `sin` at a fraction of that, and picks up a breath of
/// roll and nose-up on each footfall. The cycle is advanced by distance, so
/// it keeps step with the feet at any speed. It moves the eye only, never the
/// aim.
class ViewBob {
  /// How far the eye drops at the bottom of a full-speed footfall, metres.
  /// Kept small: a wide bob on the eye makes people ill.
  double amplitude = 0.05;

  /// The sideways sway, as a fraction of the drop.
  double swayRatio = 0.16;

  /// The walk cycle, radians.
  double phase = 0.0;

  /// How much of the sway is in, eased in and out.
  double weight = 0.0;

  /// This frame's sway of the eye.
  Vector3 offset = Vector3.zero();

  /// This frame's tilt, as a slice of the right vector added to up.
  double roll = 0.0;

  /// This frame's nose-up, as a slice of the up vector added to forward.
  double pitch = 0.0;

  /// One frame of [dt]: [walking] at [speed] against a [walkSpeed] (the
  /// weight grows to 1.7 at a sprint), [enabled] fading the sway in or out
  /// while the cycle keeps step. [cadence] scales cycles per metre, [gait]
  /// the width, [rollScale] the lean (a mount's trot throws harder).
  void update(
    double dt, {
    required bool walking,
    required double speed,
    required double walkSpeed,
    required Vector3 right,
    required Vector3 up,
    bool enabled = true,
    double cadence = 1.0,
    double gait = 1.0,
    double rollScale = 1.0,
  }) {
    final want = walking && enabled ? (speed / walkSpeed).clamp(0.0, 1.7) : 0.0;
    weight = lerpd(weight, want, math.min(1.0, dt * 9.0));
    // One cycle, two footfalls, every 3.3 m walked.
    if (walking) phase = (phase + speed * dt * 1.9 * cadence) % (math.pi * 2);
    if (weight < 0.001) {
      offset = Vector3.zero();
      roll = 0.0;
      pitch = 0.0;
      return;
    }
    final amp = weight * amplitude * gait;
    final s = math.sin(phase);
    offset = right * (s * amp * swayRatio) - up * (math.cos(phase).abs() * amp);
    roll = s * amp * 0.03 * rollScale;
    pitch = math.cos(phase - 0.2).abs() * amp * 0.05;
  }
}
