import 'package:vector_math/vector_math.dart';

import '../entities/target.dart';

/// What a rider hands what it rides, one step at a time: [wish] is the move
/// along the ground, turned by the rider's look (what a mount walks along);
/// [forward] is the move's forward axis (-1..1, forward positive) and [turn]
/// its right axis (-1..1, right positive), what a vehicle rows and steers by;
/// [sprint] is held while moving forward, [jump] while held.
typedef RideInput = ({Vector3 wish, double forward, double turn, bool sprint, bool jump});

/// Anything with a seat: a tamed mount (`Mob`), a vehicle (`Vehicle`). A
/// rider gets on when it [takes] them (`PlayerEntity.ride`), sits on its
/// [seat], moves it by [carry] every step it rides, and gets off by sneaking,
/// or when it is [gone].
abstract interface class Rideable {
  /// Who rides it, or null.
  Target? get rider;
  set rider(Target? rider);

  /// What a player reads: "Riding the horse".
  String get name;

  /// Its feet.
  Vector3 get position;

  /// How fast it moves, metres a second.
  Vector3 get velocity;

  /// Half its width: a rider gets off beside it, this far from its middle and
  /// their own half width more.
  double get halfWidth;

  /// The yaw it points, radians, as `Mob.facing`: `atan2(-x, -z)` of where it
  /// faces. A rider's body faces it while seated.
  double get facing;

  /// Whether it is out of the world, dead or removed: its rider gets off.
  bool get gone;

  /// Where its rider's feet go now.
  Vector3 seat();

  /// Whether [rider] may get on now.
  bool takes(Target rider);

  /// One step of [dt] under its rider, moved by [input].
  void carry(double dt, RideInput input);
}
