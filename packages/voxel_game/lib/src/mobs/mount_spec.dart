/// How a tamed creature carries its rider: where the rider sits, and how its
/// pace and jump answer the rider's input.
class MountSpec {
  /// A mount whose rider's feet sit [seat] metres over its own, at [speed]
  /// of its pace walking and [sprint] times that sprinting, jumping at
  /// [jumpVelocity].
  const MountSpec({required this.seat, this.speed = 1.0, this.sprint = 1.4, this.jumpVelocity = 9.0})
    : assert(seat > 0.0 && speed > 0.0 && sprint >= 1.0 && jumpVelocity > 0.0);

  /// Metres from its feet to its rider's.
  final double seat;

  /// Its ridden pace, as a share of the creature's speed.
  final double speed;

  /// What sprinting multiplies the ridden pace by.
  final double sprint;

  /// Its jump, metres a second up.
  final double jumpVelocity;
}
