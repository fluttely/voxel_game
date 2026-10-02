import 'package:vector_math/vector_math.dart';

/// Who holds a fishing line (`Bobber.owner`): the player who cast it, or
/// another player whose float a networked game draws (`RemotePlayer`).
abstract interface class Angler {
  /// Where the hand the line hangs from is drawn this frame.
  Vector3 get drawnHand;

  /// Gone from the world: its float goes with it.
  bool get removed;
}
