import 'dart:math' as math;

import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import 'rig.dart';

/// How a body plan moves: the numbers a [RigAnimator] poses with. The
/// defaults are the kit's; a game tunes its own creatures' feel here.
class RigMotion {
  /// The kit's motion.
  const RigMotion({
    this.gaitRate,
    this.wingRate = 22.0,
    this.wingSweep = 0.9,
    this.wingFold = -0.15,
    this.wingFoldSpan = 0.55,
    this.swingSeconds = 0.35,
    this.landSquash = 0.35,
    this.landSeconds = 0.2,
    this.swingNod = 0.4,
    this.swingPeck = 0.6,
  });

  /// Walk cycles, radians per metre; null for the body plan's own.
  final double? gaitRate;

  /// The wingbeat, radians a second.
  final double wingRate;

  /// How far up and down the beat carries the tip, radians.
  final double wingSweep;

  /// The folded wing's angle, radians.
  final double wingFold;

  /// How far a folded wing's span draws in (voxels cannot fold).
  final double wingFoldSpan;

  /// How long an attack swing takes, seconds.
  final double swingSeconds;

  /// How flat a blob splats the tick it lands, and how long it takes back.
  final double landSquash, landSeconds;

  /// How far a quadruped's head dips on a swing, and a bird's pecks.
  final double swingNod, swingPeck;

  /// A wing's angle at [phase], positive up, blended out of the fold by
  /// [weight].
  double wingAngle(double phase, double weight) => lerpd(wingFold, math.sin(phase) * wingSweep, weight);

  /// The body plan's own walk cycles per metre.
  static double gaitRateOf(RigKind kind) => switch (kind) {
        RigKind.bird => 4.2,
        RigKind.spider => 3.0,
        RigKind.quadruped => 2.6,
        _ => 2.2,
      };
}

/// Poses a body plan's named parts every frame (`body`, `head`, `leg0`..,
/// `arm0`, `arm1`, `wing0`, `wing1`, `tail`), whatever built them: legs trot
/// on their diagonals, alternate or walk a spider's tetrapod, wings beat in the
/// air and fold on the ground, a tail sways, arms swing and chop, a blob
/// squashes and splats. The walk eases in and out and is cycled by distance.
class RigAnimator {
  /// An animator of [parts] as a [kind]; [armRest] holds a humanoid's arms
  /// (1.4 out in front, 0 at the sides), [legFan] a spider's resting splay.
  RigAnimator(this.kind, this.parts, {this.motion = const RigMotion(), this.armRest = 0.0, List<double>? legFan})
      : legFan = legFan ?? [],
        _gaitRate = motion.gaitRate ?? RigMotion.gaitRateOf(kind);

  /// The body plan.
  final RigKind kind;

  /// The parts posed.
  final Map<String, RigPart> parts;

  /// How it moves.
  final RigMotion motion;

  /// Where a humanoid's arms hang at rest.
  final double armRest;

  /// A spider's resting splay, per leg.
  final List<double> legFan;

  final double _gaitRate;

  /// The walk cycle, radians.
  double phase = 0.0;

  /// How much of the walk is in.
  double moveWeight = 0.0;

  /// The wingbeat, radians, on its own clock.
  double wingPhase = 0.0;

  /// How much of the beat is in against the fold.
  double wingWeight = 0.0;

  /// The attack swing, 1 down to 0.
  double swing = 0.0;

  /// A blob's height over its rest (it keeps its volume).
  double squash = 1.0;

  double _landSquash = 0.0;
  bool _wasOnFloor = true;

  /// Starts an attack swing (a humanoid's arm, a quadruped's nod, a peck).
  void startSwing() => swing = 1.0;

  /// Poses the parts for one frame of [dt] at [age] seconds (the idle
  /// clock): moving at [speed], standing [onFloor] or [flying], rising at
  /// [verticalSpeed]; [lookYaw] turns the head (relative to the body), null
  /// for straight ahead. Parts are applied by the caller.
  void pose(double dt, {required double age, required double speed, bool onFloor = true, bool flying = false, double? lookYaw, double verticalSpeed = 0.0}) {
    moveWeight = lerpd(moveWeight, speed > 0.3 ? 1.0 : 0.0, math.min(1.0, dt * 8.0));
    phase += dt * speed * _gaitRate;
    final a = math.sin(phase) * 0.7 * moveWeight;
    final head = parts['head'];
    if (head != null) head.ry = lerpAngle(head.ry, (lookYaw ?? 0.0).clamp(-1.2, 1.2), math.min(1.0, dt * 5.0));
    // Wings beat in the air, fold on the ground; the tip twists over the top
    // so the beat reads as a stroke, not a hinge.
    final left = parts['wing0'], right = parts['wing1'];
    if (left != null && right != null) {
      wingWeight = lerpd(wingWeight, flying || !onFloor ? 1.0 : 0.0, math.min(1.0, dt * 8.0));
      if (wingWeight > 0.001) wingPhase = (wingPhase + dt * motion.wingRate) % (math.pi * 2);
      final angle = motion.wingAngle(wingPhase, wingWeight);
      final twist = math.cos(wingPhase) * 0.3 * wingWeight;
      final span = lerpd(motion.wingFoldSpan, 1.0, wingWeight);
      left
        ..rz = -angle
        ..rx = twist
        ..sx = span;
      right
        ..rz = angle
        ..rx = twist
        ..sx = span;
    }
    // Four legs trot on their diagonals, two alternate, eight walk the
    // alternating tetrapod: four reach while four push.
    for (var i = 0; i < 8; i++) {
      final p = parts['leg$i'];
      if (p == null) continue;
      if (kind == RigKind.spider) {
        final side = i % 2 == 0 ? 1.0 : -1.0;
        final group = ((i % 2) ^ ((i ~/ 2) % 2)) == 0 ? 1.0 : -1.0;
        p.rz = math.sin(phase) * 0.3 * group * moveWeight + math.sin(age * 1.7 + i) * 0.05;
        p.ry = legFan[i] + math.cos(phase) * 0.3 * group * side * moveWeight;
      } else {
        final stride = ((i % 2 == 0) == (i < 2)) ? a : -a;
        // A bird in the air tucks its legs back instead of pedalling.
        p.rx = kind == RigKind.bird ? lerpd(stride, 0.9, wingWeight) : stride;
      }
    }
    final tail = parts['tail'];
    if (tail != null) {
      tail.ry = math.sin(age * 1.6) * 0.18 + a * 0.35;
      tail.rx = -0.5 * wingWeight + math.cos(phase) * 0.12 * moveWeight;
    }
    swing = math.max(swing - dt / motion.swingSeconds, 0.0);
    switch (kind) {
      case RigKind.quadruped:
        // The body rises twice a cycle, the head nods a beat behind.
        final lift = math.sin(phase * 2.0) * 0.02 * moveWeight;
        parts['body']
          ?..offY = lift
          ..rx = -a * 0.06;
        head
          ?..offY = lift * 0.8
          ..rx = math.sin(phase * 2.0 + 0.7) * 0.10 * moveWeight - swing * motion.swingNod;
      case RigKind.humanoid:
        // Arms at the sides swing with the stride; arms held out only stir.
        final reach = armRest == 0.0 ? 0.8 : 0.3;
        final chop = math.sin((1.0 - swing) * math.pi) * 1.3 * (swing > 0.0 ? 1.0 : 0.0);
        parts['arm0']?.rx = armRest - a * reach + chop;
        parts['arm1']?.rx = armRest + a * reach;
        final bob = math.sin(phase).abs() * 0.02 * moveWeight;
        parts['body']
          ?..ry = -a * 0.12
          ..offY = bob;
        head?.offY = bob;
      case RigKind.blob:
        if (onFloor && !_wasOnFloor) _landSquash = motion.landSquash;
        _landSquash = math.max(_landSquash - dt / motion.landSeconds, 0.0);
        final rise = onFloor ? 0.0 : (verticalSpeed * 0.02).clamp(-0.12, 0.18);
        squash = 1.0 + math.sin(age * 6.0) * 0.05 + rise - _landSquash;
      case RigKind.bird:
        // The head thrown forward, the body catching up.
        head
          ?..offZ = -math.sin(phase * 2.0) * 0.035 * moveWeight
          ..rx = math.cos(phase * 2.0) * 0.12 * moveWeight + swing * motion.swingPeck;
        parts['body']?.rx = -0.15 * wingWeight + math.sin(phase * 2.0) * 0.05 * moveWeight;
      case RigKind.spider:
        break;
    }
    _wasOnFloor = onFloor;
  }
}
