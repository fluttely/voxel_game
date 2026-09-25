import 'package:vector_math/vector_math.dart';

import '../grid/block_collision.dart';
import '../grid/block_shape.dart';
import '../grid/voxel_block_table.dart';
import '../math/ivec3.dart';
import 'voxel_body.dart';

/// A voxel raycast hit: the cell, the face normal it was entered through, and
/// the distance travelled to that face.
class RayHit {
  /// A hit on [block], entered through the face whose normal is [normal].
  RayHit(this.block, this.normal, this.distance);

  /// The cell hit.
  final IVec3 block;

  /// The normal of the face the ray entered through, one axis at ±1; zero when
  /// the ray starts inside the block.
  final IVec3 normal;

  /// The ray parameter at that face: a distance when the direction is a unit vector.
  final double distance;
}

/// Grid traversal (Amanatides & Woo) through a [VoxelQuery].
abstract final class VoxelRaycast {
  /// The first cell along the ray holding a block that is neither air nor a
  /// liquid, within [reachDist]; null when there is none.
  static RayHit? solid(VoxelQuery q, Vector3 origin, Vector3 direction, double reachDist) {
    var bx = origin.x.floor(), by = origin.y.floor(), bz = origin.z.floor();
    final sx = direction.x > 0.0 ? 1 : -1, sy = direction.y > 0.0 ? 1 : -1, sz = direction.z > 0.0 ? 1 : -1;
    final tdx = direction.x.abs() < 1e-9 ? double.infinity : (1.0 / direction.x).abs();
    final tdy = direction.y.abs() < 1e-9 ? double.infinity : (1.0 / direction.y).abs();
    final tdz = direction.z.abs() < 1e-9 ? double.infinity : (1.0 / direction.z).abs();
    var tmx = _distToBoundary(origin.x, direction.x, bx);
    var tmy = _distToBoundary(origin.y, direction.y, by);
    var tmz = _distToBoundary(origin.z, direction.z, bz);
    var normal = IVec3.zero;
    var travelled = 0.0;
    while (travelled <= reachDist) {
      final id = q.getBlockXYZ(bx, by, bz);
      if (id != VoxelBlockTable.air && !q.table.isLiquid(id)) return RayHit(IVec3(bx, by, bz), normal, travelled);
      if (tmx < tmy && tmx < tmz) {
        bx += sx;
        travelled = tmx;
        tmx += tdx;
        normal = IVec3(-sx, 0, 0);
      } else if (tmy < tmz) {
        by += sy;
        travelled = tmy;
        tmy += tdy;
        normal = IVec3(0, -sy, 0);
      } else {
        bz += sz;
        travelled = tmz;
        tmz += tdz;
        normal = IVec3(0, 0, -sz);
      }
    }
    return null;
  }

  /// The first liquid cell along the ray, stopping at the first solid block;
  /// null when there is none within [reachDist].
  static IVec3? liquid(VoxelQuery q, Vector3 origin, Vector3 direction, double reachDist) {
    var block = IVec3.floor(origin);
    final stepX = direction.x > 0 ? 1 : -1, stepY = direction.y > 0 ? 1 : -1, stepZ = direction.z > 0 ? 1 : -1;
    final tdx = direction.x == 0 ? double.infinity : (1.0 / direction.x).abs();
    final tdy = direction.y == 0 ? double.infinity : (1.0 / direction.y).abs();
    final tdz = direction.z == 0 ? double.infinity : (1.0 / direction.z).abs();
    var tmx = _distToBoundary(origin.x, direction.x, block.x);
    var tmy = _distToBoundary(origin.y, direction.y, block.y);
    var tmz = _distToBoundary(origin.z, direction.z, block.z);
    var travelled = 0.0;
    while (travelled <= reachDist) {
      final id = q.getBlockXYZ(block.x, block.y, block.z);
      if (q.table.isLiquid(id)) return block;
      if (id != VoxelBlockTable.air && q.table.isSolid(id)) return null;
      if (tmx < tmy && tmx < tmz) {
        block = block + IVec3(stepX, 0, 0);
        travelled = tmx;
        tmx += tdx;
      } else if (tmy < tmz) {
        block = block + IVec3(0, stepY, 0);
        travelled = tmy;
        tmy += tdy;
      } else {
        block = block + IVec3(0, 0, stepZ);
        travelled = tmz;
        tmz += tdz;
      }
    }
    return null;
  }

  /// How far along the ray the first collision box stands — the first thing
  /// that would stop a body — or null when the line is clear for [reachDist].
  ///
  /// This is the reach every swing and every bite obeys: what is nearest wins,
  /// so a creature behind a wall is out of reach until the wall is gone. It
  /// reads the boxes, not the cells, so the line passes through the gap in a
  /// fence, an open door and a flower, exactly where a body passes. A box the
  /// ray starts inside is not in the way: a shoulder in a wall still swings.
  static double? barrier(
    VoxelQuery q,
    Vector3 origin,
    Vector3 direction,
    double reachDist, {
    bool fenceBarrier = false,
  }) {
    var bx = origin.x.floor(), by = origin.y.floor(), bz = origin.z.floor();
    final sx = direction.x > 0.0 ? 1 : -1, sy = direction.y > 0.0 ? 1 : -1, sz = direction.z > 0.0 ? 1 : -1;
    final tdx = direction.x.abs() < 1e-9 ? double.infinity : (1.0 / direction.x).abs();
    final tdy = direction.y.abs() < 1e-9 ? double.infinity : (1.0 / direction.y).abs();
    final tdz = direction.z.abs() < 1e-9 ? double.infinity : (1.0 / direction.z).abs();
    var tmx = _distToBoundary(origin.x, direction.x, bx);
    var tmy = _distToBoundary(origin.y, direction.y, by);
    var tmz = _distToBoundary(origin.z, direction.z, bz);
    var travelled = 0.0;
    while (travelled <= reachDist) {
      // y < 0 is solid rock.
      final boxes = by < 0 ? const [CollisionBox.full] : collisionBoxesAt(q, bx, by, bz, fenceBarrier: fenceBarrier);
      var near = double.infinity;
      for (final box in boxes) {
        final t = _boxEntry(box.shifted(bx, by, bz), origin, direction);
        if (t > 0.0 && t < near) near = t;
      }
      // The cells are walked in order and no two overlap, so the first cell
      // holding a box holds the nearest one.
      if (near <= reachDist) return near;
      if (tmx < tmy && tmx < tmz) {
        bx += sx;
        travelled = tmx;
        tmx += tdx;
      } else if (tmy < tmz) {
        by += sy;
        travelled = tmy;
        tmy += tdy;
      } else {
        bz += sz;
        travelled = tmz;
        tmz += tdz;
      }
    }
    return null;
  }

  /// Where the ray enters [box], or -1 when it misses it, starts inside it or
  /// leaves it behind.
  static double _boxEntry(CollisionBox box, Vector3 origin, Vector3 direction) {
    var near = double.negativeInfinity;
    var far = double.infinity;
    for (var axis = 0; axis < 3; axis++) {
      final d = direction[axis];
      final inv = d != 0.0 ? 1.0 / d : double.infinity;
      final a = (box.min(axis) - origin[axis]) * inv;
      final b = (box.max(axis) - origin[axis]) * inv;
      final lo = a < b ? a : b;
      final hi = a > b ? a : b;
      if (lo > near) near = lo;
      if (hi < far) far = hi;
    }
    return far < near || near <= 0.0 ? -1.0 : near;
  }

  static double _distToBoundary(double o, double d, int cell) {
    if (d.abs() < 1e-9) return double.infinity;
    return d > 0.0 ? ((cell + 1.0 - o) / d) : ((cell - o) / d);
  }
}
