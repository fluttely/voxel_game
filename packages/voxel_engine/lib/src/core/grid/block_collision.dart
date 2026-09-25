import '../physics/voxel_body.dart';
import 'block_shape.dart';
import 'voxel_block_table.dart';

/// The sides of a fence that reach toward a neighbour, as bits of a mask.
abstract final class FenceJoin {
  /// Toward -x.
  static const int west = 1;

  /// Toward +x.
  static const int east = 2;

  /// Toward -z.
  static const int north = 4;

  /// Toward +z.
  static const int south = 8;
}

/// The sides of the fence at ([x], [y], [z]) that join a neighbour: a fence or
/// an opaque block beside it. The mesher draws its rails by the same rule, and
/// the outline and the collider read it here, so the three cannot disagree.
int fenceJoinsAt(VoxelQuery q, int x, int y, int z) {
  final table = q.table;
  bool joins(int dx, int dz) {
    final n = q.getBlockXYZ(x + dx, y, z + dz);
    return n != VoxelBlockTable.air && (table.isOpaque(n) || table.shapeOf(n) == BlockShape.fence);
  }

  return (joins(-1, 0) ? FenceJoin.west : 0) |
      (joins(1, 0) ? FenceJoin.east : 0) |
      (joins(0, -1) ? FenceJoin.north : 0) |
      (joins(0, 1) ? FenceJoin.south : 0);
}

/// How tall a fence stands to a body with [VoxelBody.fenceBarrier]: above
/// any jump an animal makes (8 m/s rises 1.23 m), so a pen holds it while the
/// player, who meets the drawn block, jumps onto the rail.
const double fenceBarrierHeight = 1.5;

/// The boxes a fence with [joins] stops a body with, in the block's own 0..1
/// space: the post, stretched along each axis to the sides it joins. Every
/// piece is as tall as the post, one block, or [fenceBarrierHeight] when
/// [barrier] is set. Shared: never mutate.
List<CollisionBox> fenceBoxesOf(int joins, {bool barrier = false}) => (barrier ? _barrierBoxes : _fenceBoxes)[joins];

final List<List<CollisionBox>> _fenceBoxes = _fenceTable(CollisionBox.fencePost.y1);
final List<List<CollisionBox>> _barrierBoxes = _fenceTable(fenceBarrierHeight);

List<List<CollisionBox>> _fenceTable(double top) => List.unmodifiable([
  for (var joins = 0; joins < 16; joins++) List<CollisionBox>.unmodifiable(_buildFenceBoxes(joins, top)),
]);

List<CollisionBox> _buildFenceBoxes(int joins, double top) {
  const post = CollisionBox.fencePost;
  final alongX = joins & (FenceJoin.west | FenceJoin.east) != 0;
  final alongZ = joins & (FenceJoin.north | FenceJoin.south) != 0;
  if (!alongX && !alongZ) return [CollisionBox(post.x0, post.y0, post.z0, post.x1, top, post.z1)];
  return [
    if (alongX)
      CollisionBox(
        joins & FenceJoin.west != 0 ? 0 : post.x0,
        post.y0,
        post.z0,
        joins & FenceJoin.east != 0 ? 1 : post.x1,
        top,
        post.z1,
      ),
    if (alongZ)
      CollisionBox(
        post.x0,
        post.y0,
        joins & FenceJoin.north != 0 ? 0 : post.z0,
        post.x1,
        top,
        joins & FenceJoin.south != 0 ? 1 : post.z1,
      ),
  ];
}

/// How far a ladder's rungs stand off its wall, and where its rails run
/// across it.
const double ladderDepth = 0.12, ladderRail0 = 0.1875, ladderRail1 = 0.8125;

/// The box a ladder at ([x], [y], [z]) fills, in the block's own 0..1 space:
/// its rails and rungs, lying on the wall it hangs from. The wall is the first
/// opaque neighbour of -x, +x, +z, else -z — the mesher's order. A body in
/// the ladder's cell still stands in it (0.12 deep), so it keeps climbing.
CollisionBox ladderBoxAt(VoxelQuery q, int x, int y, int z) {
  final table = q.table;
  bool opaqueAt(int dx, int dz) => table.isOpaque(q.getBlockXYZ(x + dx, y, z + dz));
  if (opaqueAt(-1, 0)) return const CollisionBox(0, 0, ladderRail0, ladderDepth, 1, ladderRail1);
  if (opaqueAt(1, 0)) return const CollisionBox(1 - ladderDepth, 0, ladderRail0, 1, 1, ladderRail1);
  if (opaqueAt(0, 1)) return const CollisionBox(ladderRail0, 0, 1 - ladderDepth, ladderRail1, 1, 1);
  return const CollisionBox(ladderRail0, 0, 0, ladderRail1, 1, ladderDepth);
}

/// The boxes a body collides with at the world cell ([x], [y], [z]), in the
/// block's own 0..1 space. Most blocks answer from their shape alone
/// ([VoxelBlockTable.collisionBoxes]); a fence and a ladder also read their
/// neighbours. [fenceBarrier] raises a fence to [fenceBarrierHeight].
List<CollisionBox> collisionBoxesAt(VoxelQuery q, int x, int y, int z, {bool fenceBarrier = false}) {
  final table = q.table;
  final id = q.getBlockXYZ(x, y, z);
  final shape = table.shapeOf(id);
  if (shape == BlockShape.fence && table.isSolid(id)) {
    return fenceBoxesOf(fenceJoinsAt(q, x, y, z), barrier: fenceBarrier);
  }
  if (shape == BlockShape.ladder) return [ladderBoxAt(q, x, y, z)];
  return table.collisionBoxes(id);
}
