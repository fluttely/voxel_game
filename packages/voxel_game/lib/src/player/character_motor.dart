import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

/// How a body moves on foot.
class MotorTuning {
  /// The kit's defaults: a walker paced like a block-sandbox player.
  const MotorTuning({
    this.jumpVelocity = 8.6,
    this.groundAccel = 14.0,
    this.airAccel = 6.0,
    this.swimStroke = 20.0,
    this.swimRise = 4.0,
    this.climbSpeed = 3.2,
    this.autoStep = true,
    this.glideFall = 1.6,
    this.flySpeed = 12.0,
    this.flyAccel = 10.0,
  });

  /// Launch speed of a jump, metres a second (8.6 clears a block and a bit).
  final double jumpVelocity;

  /// How fast the walk catches up with the wish on the ground (per second).
  final double groundAccel;

  /// ...and in the air.
  final double airAccel;

  /// Upward acceleration while swimming up.
  final double swimStroke;

  /// The fastest a swimmer rises.
  final double swimRise;

  /// Speed on a ladder.
  final double climbSpeed;

  /// Whether a step (a slab, a block) walked into is jumped by itself.
  final bool autoStep;

  /// The fastest a glider sinks, metres a second.
  final double glideFall;

  /// Vertical speed of a flyer rising or sinking.
  final double flySpeed;

  /// How fast a flyer's drift catches up with the wish (per second).
  final double flyAccel;
}

/// What one [CharacterMotor.step] did that its owner answers: a landing
/// after a fall (for fall damage), a jump.
class MotorEvents {
  /// Metres fallen before this step's landing, 0 without one.
  double landedAfter = 0.0;

  /// Whether the body jumped this step (a key or an auto step).
  bool jumped = false;
}

/// The on-foot rules of a body in a voxel world, shared by the player and
/// every walking creature: gravity and swimming, jumping, climbing ladders,
/// walking toward a wish at a speed, auto-jumping steps (a half step hopped
/// under double gravity, a full block jumped), launching out of water over a
/// bank, and keeping the height a fall started from.
class CharacterMotor {
  /// A motor for [body].
  CharacterMotor(this.body, [this.tuning = const MotorTuning()]) : _fallStart = body.position.y;

  /// The body moved.
  final VoxelBody body;

  /// How it moves.
  final MotorTuning tuning;

  bool _hopping = false;
  bool _leavingWater = false;
  double _sinceWater = 1.0;
  double _fallStart;

  /// Seconds left in which a shove carries the body and the wish does not
  /// steer it (knockback).
  double stagger = 0.0;

  /// Whether the body is on a ladder this step.
  bool climbing = false;

  /// Whether the body glided this step (its fall capped).
  bool gliding = false;

  /// In a liquid and off the floor, or with the head under: swimming, not
  /// wading.
  bool get swimming => body.inLiquid && !body.wading;

  /// Pushes the body by [velocity] and lets it carry for [seconds].
  void shove(Vector3 velocity, [double seconds = 0.3]) {
    body.velocity.setFrom(velocity);
    stagger = seconds;
  }

  /// Launches a jump from where the body stands, at [speed] or the tuning's.
  void jump([double? speed]) {
    body.velocity.y = speed ?? tuning.jumpVelocity;
    _fallStart = body.position.y;
  }

  /// Forgets the fall so far (the body was put somewhere, or sat down).
  void resetFall() => _fallStart = body.position.y;

  /// Whether a glide would hold now: in the air, out of liquid, falling.
  bool get canGlide => !body.onFloor && !body.inLiquid && body.velocity.y < 0.0;

  /// One step of [dt]: walk toward [wish] (horizontal, length up to 1) at
  /// [speed], jumping while [jump] is held, sneaking (no auto step up a full
  /// block) with [sneak]; [onLadder] makes the body climb (a wall climbed is a
  /// ladder too). [glide] caps the fall at [MotorTuning.glideFall] and counts
  /// as footing for the fall's height; [accel] replaces the walk's catch-up
  /// rate for this step (a dash, a glide's slow steering), and [jumpSpeed]
  /// the launch of a jump off the floor (a mount's leap). A swimmer pushing
  /// at a bank launches over it while [jump] is held, or whenever
  /// [leaveWater] says so (a creature always wants out).
  MotorEvents step(
    double dt, {
    required Vector3 wish,
    required double speed,
    bool jump = false,
    bool sneak = false,
    bool onLadder = false,
    bool glide = false,
    double? accel,
    double? jumpSpeed,
    bool? leaveWater,
  }) {
    final events = MotorEvents();
    final b = body;
    climbing = false;
    gliding = false;
    if (onLadder) {
      b.velocity.y = jump ? tuning.climbSpeed : (sneak ? -tuning.climbSpeed : 0.0);
      climbing = jump;
    } else if (_leavingWater) {
      b.velocity.y -= b.gravity * dt;
    } else if (swimming) {
      if (jump) {
        b.velocity.y = math.min(b.velocity.y + tuning.swimStroke * dt, tuning.swimRise);
      } else {
        b.applyGravity(dt);
      }
    } else {
      b.applyGravity(dt);
      if (_hopping) b.applyGravity(dt);
      if (jump && b.onFloor) {
        this.jump(jumpSpeed);
        events.jumped = true;
      }
    }
    if (glide) {
      gliding = true;
      b.velocity.y = math.max(b.velocity.y, -tuning.glideFall);
    }
    final rate = accel ?? (b.onFloor || _hopping ? tuning.groundAccel : tuning.airAccel);
    if (stagger <= 0.0) {
      b.velocity.x = lerpd(b.velocity.x, wish.x * speed, math.min(dt * rate, 1.0));
      b.velocity.z = lerpd(b.velocity.z, wish.z * speed, math.min(dt * rate, 1.0));
    }
    final wasFloor = b.onFloor;
    b.move(dt);
    if (b.onFloor || b.inLiquid || climbing) _hopping = false;
    if (b.onFloor || climbing || b.velocity.y <= 0.0) _leavingWater = false;
    final wishing = wish.x * wish.x + wish.z * wish.z > 0.01;
    if (tuning.autoStep && wishing && !climbing && !b.inLiquid) {
      final lift = b.stepAhead(fullBlock: !sneak);
      if (lift > 0.0) {
        b.velocity.y = tuning.jumpVelocity;
        _hopping = lift == VoxelBody.halfStep;
        _fallStart = b.position.y;
        events.jumped = true;
      }
    }
    _sinceWater = b.inLiquid ? 0.0 : _sinceWater + dt;
    if (b.hitWall &&
        _sinceWater < 0.5 &&
        !b.onFloor &&
        (leaveWater ?? jump) &&
        wishing &&
        !climbing &&
        !_leavingWater) {
      // Out of the water over a bank: the lowest lift that fits, and a
      // quarter block to spare. A wall taller than 1.9 is never climbed.
      for (var lift = 0.1; lift <= 1.9; lift += 0.1) {
        if (!b.stepFits(lift)) continue;
        b.velocity.y = math.sqrt(2.0 * b.gravity * (lift + 0.25));
        _leavingWater = true;
        _fallStart = b.position.y;
        break;
      }
    }
    if (!wasFloor && b.onFloor && !b.inLiquid) events.landedAfter = math.max(0.0, _fallStart - b.position.y);
    // The fall is measured from the highest point since the feet last had
    // footing: a jump's peak, a ledge walked off, or wherever the body was put.
    if (b.onFloor || climbing || gliding || b.inLiquid) {
      _fallStart = b.position.y;
    } else {
      _fallStart = math.max(_fallStart, b.position.y);
    }
    stagger = math.max(stagger - dt, 0.0);
    return events;
  }

  /// One step of free flight (creative): no gravity, drifting toward [wish]
  /// at [speed], rising while [rise] is held and sinking while [sink] is.
  /// A flyer never falls, so it never lands hurt.
  void fly(double dt, {required Vector3 wish, required double speed, bool rise = false, bool sink = false}) {
    final b = body;
    climbing = false;
    gliding = false;
    b.velocity.y = (rise ? tuning.flySpeed : 0.0) - (sink ? tuning.flySpeed : 0.0);
    if (stagger <= 0.0) {
      b.velocity.x = lerpd(b.velocity.x, wish.x * speed, math.min(dt * tuning.flyAccel, 1.0));
      b.velocity.z = lerpd(b.velocity.z, wish.z * speed, math.min(dt * tuning.flyAccel, 1.0));
    }
    b.move(dt);
    _fallStart = b.position.y;
    stagger = math.max(stagger - dt, 0.0);
  }

  /// Steps without walking: gravity, swimming and landing only.
  MotorEvents idle(double dt) => step(dt, wish: Vector3.zero(), speed: 0.0);
}
