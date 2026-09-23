import '../physics/voxel_body.dart';
import 'block_collision.dart';
import 'block_shape.dart';
import 'chunk_size.dart';

/// The box an aimed block's outline is drawn around, in world space: the
/// bounds of what the chunk mesher actually draws in the cell, not the cell.
/// A torch gets a thin post, a slab half a cube, a door a panel, a plant the
/// sheet it grows. Shapes that lean on a neighbour (a wall torch, a ladder)
/// or join one (a fence) read the same neighbours, in the same order, as the
/// mesher does, so the box and the mesh cannot disagree.
CollisionBox selectionBoxAt(VoxelQuery q, int x, int y, int z) {
  final table = q.table;
  final shape = table.shapeOf(q.getBlockXYZ(x, y, z));
  bool opaqueAt(int dx, int dz) => table.isOpaque(q.getBlockXYZ(x + dx, y, z + dz));
  // The mesher's per-cell plant jitter is keyed on chunk-local x / z.
  final lx = x % ChunkSize.sizeX, lz = z % ChunkSize.sizeZ;
  final local = switch (shape) {
    BlockShape.cross => _plant(lx, y, lz, 0.28, 0.55 + ((lx + lz) % 3) * 0.1),
    BlockShape.flower => _plant(lx, y, lz, 0.14, 0.62),
    BlockShape.torch => const CollisionBox(0.4, 0, 0.4, 0.6, 0.62, 0.6),
    BlockShape.wallTorch => opaqueAt(-1, 0)
        ? const CollisionBox(0.0, 0.3, 0.4, 0.2, 0.85, 0.6)
        : opaqueAt(1, 0)
            ? const CollisionBox(0.8, 0.3, 0.4, 1.0, 0.85, 0.6)
            : opaqueAt(0, -1)
                ? const CollisionBox(0.4, 0.3, 0.0, 0.6, 0.85, 0.2)
                : const CollisionBox(0.4, 0.3, 0.8, 0.6, 0.85, 1.0),
    BlockShape.panelZ => const CollisionBox(0, 0, 0, 1, 1, _panel),
    BlockShape.panelX => const CollisionBox(0, 0, 0, _panel, 1, 1),
    BlockShape.slab => const CollisionBox(0, 0, 0, 1, 0.5, 1),
    BlockShape.wire ||
    BlockShape.railNs ||
    BlockShape.railEw ||
    BlockShape.railNe ||
    BlockShape.railNw ||
    BlockShape.railSe ||
    BlockShape.railSw =>
      const CollisionBox(0, 0, 0, 1, 0.125, 1),
    BlockShape.railSlopeN || BlockShape.railSlopeE || BlockShape.railSlopeS || BlockShape.railSlopeW =>
      const CollisionBox(0, 0, 0, 1, 0.875, 1),
    BlockShape.fence => _fence(q, x, y, z),
    BlockShape.ladder => ladderBoxAt(q, x, y, z),
    BlockShape.cube ||
    BlockShape.liquid ||
    BlockShape.stairsN ||
    BlockShape.stairsE ||
    BlockShape.stairsS ||
    BlockShape.stairsW =>
      CollisionBox.full,
  };
  return local.shifted(x, y, z);
}

/// A door or hatch panel's thickness.
const double _panel = 0.1875;

CollisionBox _plant(int lx, int y, int lz, double half, double top) {
  final cx = 0.5 + ((lx * 7 + lz * 13 + y) % 5) * 0.06 - 0.12;
  final cz = 0.5 + ((lx * 3 + lz * 11) % 5) * 0.06 - 0.12;
  return CollisionBox(cx - half, 0, cz - half, cx + half, top, cz + half);
}

CollisionBox _fence(VoxelQuery q, int x, int y, int z) {
  const p0 = 0.375, p1 = 0.625;
  final joins = fenceJoinsAt(q, x, y, z);
  return CollisionBox(
    joins & FenceJoin.west != 0 ? 0 : p0,
    0,
    joins & FenceJoin.north != 0 ? 0 : p0,
    joins & FenceJoin.east != 0 ? 1 : p1,
    1,
    joins & FenceJoin.south != 0 ? 1 : p1,
  );
}
