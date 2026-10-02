import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import 'rideable.dart';
import 'vehicle.dart';
import 'vehicle_spec.dart';

/// A boat of a [BoatSpec]: it floats on liquid and falls through air; its
/// rider rows it by the move's forward axis and steers it by its right axis
/// (`RideInput.forward`, `turn`), and without one it coasts to rest. It waits
/// while its chunk is not loaded (unloaded reads as air: it would fall). Its
/// hull rolls into a turn and bobs on the water, only to the eye.
///
/// Whether it is on liquid is its own probe, [afloat], not the body's
/// `inLiquid`: that one is sensed 0.3 m over the soles, and a boat rides
/// higher than that.
class Boat extends Vehicle {
  /// A boat of [spec] at [at], pointing [facing].
  Boat(this.spec, super.at, {super.facing});

  @override
  final BoatSpec spec;

  /// How fast the vertical speed eases toward [BoatSpec.rise] while the
  /// bottom is under the surface, and toward 0 once above it, a second.
  static const double riseEase = 5.0, settleEase = 6.0;

  /// The hull's roll, radians, at a full turn rowed forward, and how fast it
  /// eases there, a second.
  static const double rollPerTurn = 0.12, rollEase = 4.0;

  /// How far the hull bobs on liquid, metres, and how fast, radians a second.
  static const double bobHeight = 0.03, bobRate = 2.0;

  /// Metres under its feet the [afloat] probe reads.
  static const double draught = 0.1;

  /// Metres over its feet the bottom it rises by is: liquid there, it rises.
  static const double keel = 0.15;

  /// Whether liquid is under it, [draught] below its feet or less: it rows at
  /// [BoatSpec.liquidSpeed], settles instead of falling, and bobs.
  bool get afloat => _liquidAt(position.y - draught);

  double _roll = 0.0;
  double _time = 0.0;

  bool _liquidAt(double y) {
    final world = game.world;
    return world.table.isLiquid(world.getBlockXYZ(position.x.floor(), y.floor(), position.z.floor()));
  }

  @override
  void tick(VoxelGame game, double dt) {
    // Its rider moved it this step (carry).
    if (rider != null) return;
    _float(dt, forward: 0.0, turn: 0.0, rowed: false);
  }

  @override
  void carry(double dt, RideInput input) => _float(dt, forward: input.forward, turn: input.turn, rowed: true);

  void _float(double dt, {required double forward, required double turn, required bool rowed}) {
    final world = game.world;
    if (!world.isLoaded(IVec3.floor(position))) return;
    _time += dt;
    final floating = afloat;
    if (_liquidAt(position.y + keel)) {
      velocity.y = lerpd(velocity.y, spec.rise, math.min(1.0, dt * riseEase));
    } else if (floating) {
      velocity.y = lerpd(velocity.y, 0.0, math.min(1.0, dt * settleEase));
    } else {
      applyGravity(dt);
    }
    if (rowed) {
      // Right (turn +1) turns it clockwise seen from above.
      facing -= turn * spec.turnSpeed * dt;
      final speed = forward * (floating ? spec.liquidSpeed : spec.landSpeed);
      final k = math.min(1.0, dt * spec.acceleration);
      velocity.x = lerpd(velocity.x, -math.sin(facing) * speed, k);
      velocity.z = lerpd(velocity.z, -math.cos(facing) * speed, k);
    } else {
      final k = math.min(1.0, dt * spec.coast);
      velocity.x = lerpd(velocity.x, 0.0, k);
      velocity.z = lerpd(velocity.z, 0.0, k);
    }
    move(dt);
    if (position.y < -10.0) removed = true;
    _roll = lerpd(_roll, -turn * rollPerTurn * forward, math.min(1.0, dt * rollEase));
    _rock();
    syncNode(yaw: facing);
  }

  /// The hull's roll and bob, under the node that turns it.
  void _rock() {
    final m = model;
    if (m == null) return;
    final bob = afloat ? math.sin(_time * bobRate + position.x) * bobHeight : 0.0;
    _lift.setValues(0.0, bob, 0.0);
    eulerYXZInto(_tilt, 0.0, 0.0, _roll);
    m.mutateLocalTransform(_compose);
  }

  static final Vector3 _lift = Vector3.zero();
  static final Quaternion _tilt = Quaternion.identity();
  static void _compose(Matrix4 m) => m.setFromTranslationRotation(_lift, _tilt);
}
