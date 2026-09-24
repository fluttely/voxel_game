import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/signals.dart';

import '../core/blocks.dart';
import '../world/voxel_world.dart';

/// Stage 28: the rail graph (Godot `src/game/rails.gd`). VK7.3: voxel_signals'
/// [RailGraph] over this game's rail rows (`rail_<shape>`, the two powered
/// straights and their `_on` states); these statics keep the names every
/// caller used.
class Rails {
  Rails._();

  static const IVec3 n = RailGraph.n;
  static const IVec3 s = RailGraph.s;
  static const IVec3 e = RailGraph.e;
  static const IVec3 w = RailGraph.w;
  static const List<IVec3> four = RailGraph.four;

  /// Orientation suffix -> the two ends. A slope's high end carries dy = +1.
  static const Map<String, List<IVec3>> ends = RailGraph.ends;

  static final RailGraph graph = RailGraph({
    for (var i = 0; i < Blocks.count; i++)
      if (Blocks.isRail(i)) i: _variant(Blocks.idOf(i)),
  });

  static RailVariant _variant(String name) {
    final on = name.endsWith('_on');
    final bare = on ? name.substring(0, name.length - 3) : name;
    final powered = bare.startsWith('powered_rail_');
    return RailVariant(powered ? 'powered_rail' : 'rail', bare.substring(powered ? 'powered_rail_'.length : 'rail_'.length), on: on);
  }

  /// "ns", "ew", "ne", ..., "slope_w" of a rail id.
  static String suffixOf(int id) => graph.shapeOf(id);

  /// The rail id of [baseId]'s kind (and state) turned to [suffix]. A powered
  /// rail only has the two straights.
  static int withSuffix(int baseId, String suffix) => graph.withShape(baseId, suffix);

  /// The two ends a rail joins, as steps from its cell.
  static List<IVec3> connections(int id) => graph.connections(id);

  static bool isRailAt(VoxelWorld world, IVec3 c) => graph.isRail(world.getBlock(c));

  static IVec3 flat(IVec3 d) => IVec3(d.x, 0, d.z);

  static IVec3 nextCell(VoxelWorld world, IVec3 cell, IVec3 end) => graph.nextCell(world, cell, end);

  static IVec3 endToward(VoxelWorld world, IVec3 cell, IVec3 from) => graph.endToward(world, cell, from);

  static int orient(VoxelWorld world, IVec3 cell, int baseId) => graph.orient(world, cell, baseId);

  static List<IVec3> neighbours(IVec3 cell) => RailGraph.neighbours(cell);

  static void refresh(VoxelWorld world, IVec3 c) => graph.refresh(world, c);

  static int place(VoxelWorld world, IVec3 cell, int baseId) => graph.place(world, cell, baseId);

  static void removed(VoxelWorld world, IVec3 cell) => graph.removed(world, cell);
}
