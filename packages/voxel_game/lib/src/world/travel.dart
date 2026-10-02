import 'package:vector_math/vector_math.dart';

import '../spec/portal_spec.dart';

/// Where the player stands between dimensions: one state at a time, changed
/// by `VoxelGame.step` (a portal stood in, a world loaded around an arrival)
/// and by `VoxelGame.travel`.
sealed class Travel {
  const Travel();
}

/// In a world, in no portal.
final class Staying extends Travel {
  /// Staying.
  const Staying();
}

/// Standing in a lit [portal], [seconds] of its `PortalSpec.seconds` so far.
final class Charging extends Travel {
  /// Charging through [portal].
  const Charging(this.portal, this.seconds);

  /// The portal stood in.
  final PortalSpec portal;

  /// How long it has been stood in.
  final double seconds;

  /// How far along the trip is, 0..1.
  double get progress => portal.seconds == 0.0 ? 1.0 : (seconds / portal.seconds).clamp(0.0, 1.0);
}

/// Gone to [dimension] and waiting off the ground (`PlayerEntity.placed`
/// false) for its world to load around column ([x], [z]): then standing at
/// [exactly] when given, else at the column's arrival (`GameWorld.arrivalAt`),
/// a return portal built there when it came through [portal] and no lit one
/// is near.
final class Arriving extends Travel {
  /// Arriving in [dimension] at column ([x], [z]).
  const Arriving(this.dimension, this.x, this.z, {this.exactly, this.portal});

  /// The dimension arrived in.
  final String dimension;

  /// The column's x.
  final int x;

  /// The column's z.
  final int z;

  /// Where to stand, or null for the column's arrival.
  final Vector3? exactly;

  /// The portal come through, or null.
  final PortalSpec? portal;
}

/// Arrived, or charged, and still in a portal: no trip starts until the
/// player steps out of every portal block.
final class Lingering extends Travel {
  /// Lingering.
  const Lingering();
}
