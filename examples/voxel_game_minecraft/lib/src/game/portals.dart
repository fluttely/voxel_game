import 'package:vector_math/vector_math.dart';

import '../core/blocks.dart';
import 'package:voxel_engine/core.dart';
import '../world/voxel_world.dart';

/// Stage 29: the obsidian portal and the arrival spot, pure over a
/// [VoxelWorld]. Godot keeps these in `main.gd` (`try_light_portal`,
/// `_build_portal_at`, `portal_near`, `_find_safe_y`); here they are static so
/// the unit tests reach them without a scene, and `Game` calls them the way
/// Godot's `Main` does.
class Portals {
  Portals._();

  /// A body standing in a portal block this long travels.
  static const double seconds = 2.0;

  /// A return frame is built when no portal block is within this many blocks.
  static const int search = 16;

  static bool isPortal(int id) => id != Blocks.air && Blocks.idOf(id) == 'portal';

  /// Flint and steel at [cell]: when it is the hollow of an obsidian frame (2
  /// wide x 3 tall, in either vertical plane), fills the hollow with portal
  /// blocks. Returns how many were lit (0 when [cell] is not such a hollow).
  static int light(VoxelWorld world, IVec3 cell) {
    if (world.getBlock(cell) != Blocks.air) return 0;
    final obsidian = Blocks.indexOf('obsidian');
    for (final axis in const [IVec3(1, 0, 0), IVec3(0, 0, 1)]) {
      // Slide to the hollow's low corner along the axis and down, then check
      // the 2x3 and its frame.
      var origin = cell;
      while (world.getBlock(origin - axis) == Blocks.air && (cell - origin).length < 2) {
        origin = origin - axis;
      }
      while (world.getBlock(origin + IVec3.down) == Blocks.air && cell.y - origin.y < 3) {
        origin = origin + IVec3.down;
      }
      var ok = true;
      for (var i = 0; i < 2; i++) {
        for (var j = 0; j < 3; j++) {
          if (world.getBlock(origin + axis * i + IVec3(0, j, 0)) != Blocks.air) ok = false;
        }
      }
      for (var j = 0; j < 3; j++) {
        if (world.getBlock(origin - axis + IVec3(0, j, 0)) != obsidian ||
            world.getBlock(origin + axis * 2 + IVec3(0, j, 0)) != obsidian) {
          ok = false;
        }
      }
      for (var i = 0; i < 2; i++) {
        if (world.getBlock(origin + axis * i + IVec3.down) != obsidian ||
            world.getBlock(origin + axis * i + const IVec3(0, 3, 0)) != obsidian) {
          ok = false;
        }
      }
      if (!ok) continue;
      final portal = Blocks.indexOf('portal');
      var lit = 0;
      for (var i = 0; i < 2; i++) {
        for (var j = 0; j < 3; j++) {
          if (world.setBlock(origin + axis * i + IVec3(0, j, 0), portal)) lit += 1;
        }
      }
      return lit;
    }
    return 0;
  }

  /// A lit portal whose hollow's bottom-left cell is [cell]: a 4x5 obsidian
  /// frame in the x-y plane, the 2x3 inside filled with portal blocks, a floor
  /// under the frame and the two cells in front (south) of it cleared for
  /// whoever arrives.
  static void buildAt(VoxelWorld world, IVec3 cell) {
    final obsidian = Blocks.indexOf('obsidian');
    final portal = Blocks.indexOf('portal');
    for (var dx = -1; dx < 3; dx++) {
      for (var dy = -1; dy < 4; dy++) {
        final inside = dx >= 0 && dx <= 1 && dy >= 0 && dy <= 2;
        world.setBlock(cell + IVec3(dx, dy, 0), inside ? portal : obsidian);
      }
    }
    final floor = Blocks.indexOf(world.dimension == VoxelWorld.dimUnderworld ? 'hellstone' : 'cobblestone');
    for (var dx = -1; dx < 3; dx++) {
      for (var dz = 1; dz < 3; dz++) {
        for (var dy = 0; dy < 3; dy++) {
          world.setBlock(cell + IVec3(dx, dy, dz), Blocks.air);
        }
        if (!world.isSolid(cell + IVec3(dx, -1, dz))) world.setBlock(cell + IVec3(dx, -1, dz), floor);
      }
    }
  }

  /// The nearest portal block within [radius] of [at] among loaded chunks, or
  /// (0, -1, 0).
  static IVec3 near(VoxelWorld world, Vector3 at, int radius) {
    final portal = Blocks.indexOf('portal');
    final c = IVec3.floor(at);
    var best = const IVec3(0, -1, 0);
    var bestD = double.infinity;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dz = -radius; dz <= radius; dz++) {
        for (var dx = -radius; dx <= radius; dx++) {
          final b = c + IVec3(dx, dy, dz);
          if (world.getBlock(b) != portal) continue;
          final d = Vector3(dx.toDouble(), dy.toDouble(), dz.toDouble()).length;
          if (d < bestD) {
            bestD = d;
            best = b;
          }
        }
      }
    }
    return best;
  }

  /// The feet cell y of a spot with two air cells over a solid at column
  /// ([x], [z]): the underworld searches y 30..90 outward from 64 (then the
  /// columns around, bridging the column itself onto that floor; then carves a
  /// pocket at 64), the overworld takes the surface.
  static int findSafeY(VoxelWorld world, int x, int z, int dimension) {
    if (dimension != VoxelWorld.dimUnderworld) return world.groundHeight(x, z);
    final hellstone = Blocks.indexOf('hellstone');
    for (var r = 0; r < 5; r++) {
      for (var dz = -r; dz <= r; dz++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx.abs() != r && dz.abs() != r) continue;
          for (var step = 0; step < 61; step++) {
            final y = 64 + (step + 1) ~/ 2 * (step % 2 == 1 ? 1 : -1);
            if (y < 30 || y > 90) continue;
            final c = IVec3(x + dx, y, z + dz);
            if (world.getBlock(c) == Blocks.air &&
                world.getBlock(c + IVec3.up) == Blocks.air &&
                world.isSolid(c + IVec3.down) &&
                !world.isLiquid(c + IVec3.down)) {
              if (dx != 0 || dz != 0) {
                // Found beside the column: bridge the column itself onto the same floor.
                world.setBlock(IVec3(x, y - 1, z), hellstone);
                world.setBlock(IVec3(x, y, z), Blocks.air);
                world.setBlock(IVec3(x, y + 1, z), Blocks.air);
              }
              return y;
            }
          }
        }
      }
    }
    for (var dy = -1; dy < 3; dy++) {
      world.setBlock(IVec3(x, 64 + dy, z), dy == -1 ? hellstone : Blocks.air);
    }
    return 64;
  }
}
