/// What an item that glides does: carried in the bag, held glide in the air
/// caps the fall at [fall] and carries the body toward the look at [speed],
/// steering at [steer] (a hang glider, wings).
class Glider {
  /// A glider; the defaults are a hang glider's.
  const Glider({this.speed = 11.0, this.fall = 1.6, this.steer = 3.0})
    : assert(speed > 0.0 && fall > 0.0 && steer > 0.0, 'a glider flies forward, sinks and turns');

  /// Metres a second it carries the body forward.
  final double speed;

  /// The fastest it sinks, metres a second.
  final double fall;

  /// How fast the flight catches up with where the player steers (per second).
  final double steer;
}
