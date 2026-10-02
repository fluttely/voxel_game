import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';

import '../spec/portal_spec.dart';
import 'game_world.dart';

/// The portals of a game (`VoxelGameSpec.portals`) in its world: which block
/// is a portal of which kind, lighting a closed frame, building a lit one,
/// finding the nearest.
class Portals {
  /// The [specs] over [world]'s blocks; the spec has been checked
  /// (`VoxelGameSpec.checkDimensions`).
  Portals(this.world, List<PortalSpec> specs)
    : _byPortal = {for (final s in specs) world.blocks.indexOf(s.portal): s},
      _lighters = {for (final s in specs) s.lighter};

  /// The world.
  final GameWorld world;

  final Map<int, PortalSpec> _byPortal;
  final Set<String> _lighters;

  static const _axes = [IVec3(1, 0, 0), IVec3(0, 0, 1)];

  /// The portal whose block is at [cell], or null.
  PortalSpec? at(IVec3 cell) => _byPortal[world.getBlock(cell)];

  /// Whether [item] lights a portal.
  bool lights(String item) => _lighters.contains(item);

  /// Lights, with [item], the first portal it lights whose closed frame's
  /// hollow holds [cell] ([light]); false when none does.
  bool lightWith(String item, IVec3 cell) {
    for (final s in _byPortal.values) {
      if (s.lighter == item && light(s, cell)) return true;
    }
    return false;
  }

  /// Lights the hollow of a closed [spec] frame that holds [cell]: fills it
  /// with portal blocks. False when [cell] is in no such hollow (one of air,
  /// its frame whole along both sides, the top and the bottom; the corners
  /// may be anything).
  bool light(PortalSpec spec, IVec3 cell) {
    final origin = _hollowOf(spec, cell);
    if (origin == null) return false;
    final portal = world.blocks.indexOf(spec.portal);
    for (var i = 0; i < spec.width; i++) {
      for (var j = 0; j < spec.height; j++) {
        world.setBlock(origin.$1 + origin.$2 * i + IVec3(0, j, 0), portal);
      }
    }
    return true;
  }

  /// The low corner and the axis of the closed frame's hollow holding [cell].
  (IVec3, IVec3)? _hollowOf(PortalSpec spec, IVec3 cell) {
    final frame = world.blocks.indexOf(spec.frame);
    bool isFrame(IVec3 c) => world.getBlock(c) == frame;
    for (final axis in _axes) {
      for (var i = 0; i < spec.width; i++) {
        for (var j = 0; j < spec.height; j++) {
          final o = cell - axis * i - IVec3(0, j, 0);
          var ok = true;
          for (var a = 0; a < spec.width && ok; a++) {
            ok = isFrame(o + axis * a + IVec3.down) && isFrame(o + axis * a + IVec3(0, spec.height, 0));
            for (var b = 0; b < spec.height && ok; b++) {
              ok = world.getBlock(o + axis * a + IVec3(0, b, 0)) == BlockRegistry.air;
            }
          }
          for (var b = 0; b < spec.height && ok; b++) {
            ok = isFrame(o - axis + IVec3(0, b, 0)) && isFrame(o + axis * spec.width + IVec3(0, b, 0));
          }
          if (ok) return (o, axis);
        }
      }
    }
    return null;
  }

  /// A lit [spec] portal whose hollow's low corner is [corner], across x: the
  /// frame around it, the portal blocks in it, and the two rows in front of
  /// it (toward +z) cleared for whoever arrives, on a floor of [floor] where
  /// they stood over nothing firm.
  void build(PortalSpec spec, IVec3 corner, String floor) {
    final frame = world.blocks.indexOf(spec.frame);
    final portal = world.blocks.indexOf(spec.portal);
    for (var dx = -1; dx <= spec.width; dx++) {
      for (var dy = -1; dy <= spec.height; dy++) {
        final inside = dx >= 0 && dx < spec.width && dy >= 0 && dy < spec.height;
        world.setBlock(corner + IVec3(dx, dy, 0), inside ? portal : frame);
      }
    }
    for (var dx = -1; dx <= spec.width; dx++) {
      for (var dz = 1; dz <= 2; dz++) {
        for (var dy = 0; dy < spec.height; dy++) {
          world.setBlock(corner + IVec3(dx, dy, dz), BlockRegistry.air);
        }
        final under = corner + IVec3(dx, -1, dz);
        final id = world.getBlock(under);
        if (!world.blocks.table.isSolid(id) || world.blocks[id].isLiquid) world.setBlockNamed(under, floor);
      }
    }
  }

  /// The nearest [spec] portal block within [radius] blocks of [cell] among
  /// the loaded chunks, or null.
  IVec3? nearest(PortalSpec spec, IVec3 cell, int radius) {
    final portal = world.blocks.indexOf(spec.portal);
    IVec3? best;
    var bestD = radius * radius * 3 + 1;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dz = -radius; dz <= radius; dz++) {
        for (var dx = -radius; dx <= radius; dx++) {
          final d = dx * dx + dy * dy + dz * dz;
          if (d >= bestD) continue;
          final c = cell + IVec3(dx, dy, dz);
          if (world.getBlock(c) != portal) continue;
          best = c;
          bestD = d;
        }
      }
    }
    return best;
  }
}
