import 'package:vector_math/vector_math.dart';

import 'voxel_body.dart';
import 'voxel_raycast.dart';

/// Reach: the one rule every swing, every use and every bite obeys.
///
/// What stands nearest along the line is what is acted on, and nothing acts
/// through it. A creature behind a block is out of reach until the block is
/// broken; a block behind a creature is out of reach until the creature moves.
/// The rule is the same for everyone: the player at a crosshair, a zombie at a
/// wall, a rider on a horse.
abstract final class Reach {
  /// How far along the line the first block the crosshair can pick stands, or
  /// [double.infinity] when the line is clear for [maxDist]. Every block
  /// counts, grass and flowers included: they are mined, so they are aimed at.
  static double toBlock(VoxelQuery world, Vector3 origin, Vector3 dir, double maxDist) =>
      VoxelRaycast.solid(world, origin, dir, maxDist)?.distance ?? double.infinity;

  /// How far along the line the first block that stops a body stands. A swing
  /// crosses grass, a flower and the gap in a fence, because a body does.
  static double toBarrier(VoxelQuery world, Vector3 origin, Vector3 dir, double maxDist) =>
      VoxelRaycast.barrier(world, origin, dir, maxDist) ?? double.infinity;

  /// The nearest of [bodies] the line enters, no farther than [maxDist] and
  /// never behind [blockedAt]; null when a block — or nothing — is nearest.
  /// [inflate] grows each box, the aim's forgiveness; [accepts] leaves out what
  /// cannot be acted on at all (a dead mob, a boat with a driver).
  static T? nearestBody<T extends VoxelBody>(
    Iterable<T> bodies,
    Vector3 origin,
    Vector3 dir, {
    required double maxDist,
    double blockedAt = double.infinity,
    double inflate = 0.0,
    bool Function(T body)? accepts,
  }) {
    T? best;
    var bestD = maxDist < blockedAt ? maxDist : blockedAt;
    for (final body in bodies) {
      if (accepts != null && !accepts(body)) continue;
      final d = body.rayDistance(origin, dir, inflate);
      if (d >= 0.0 && d < bestD) {
        bestD = d;
        best = body;
      }
    }
    return best;
  }
}
