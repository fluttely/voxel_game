import 'dart:math' as math;

import 'package:voxel_engine/core.dart';

import '../spec/spec_generator.dart';
import 'dungeon.dart';

/// One room of a [DungeonPlan]: its walls stand [half] blocks from its
/// [centre] along x and z, its ceiling [half] over its floor.
typedef DungeonRoom = ({IVec3 centre, int half});

/// Where the parts of a [Dungeon] lie, in world cells: its [floor] rolled
/// from its site, its three [rooms] along x, the [spawners] of the two guard
/// rooms and the last room's [chest]. The dungeon draws from it, and a game
/// finds the same cells by it without reading the world.
class DungeonPlan {
  const DungeonPlan._(this.floor, this.rooms, this.spawners, this.chest);

  /// The plan of [dungeon] at [site], whose rolls are [roll]: the drawing's
  /// `StructureSite.roll`, or a game's `SpecGenerator.rollOf(site)`.
  factory DungeonPlan.of(Dungeon dungeon, PlacedStructure site, int Function(int salt) roll) {
    final floor = math.max(site.y - roll(1) % 14, 8);
    final rooms = [
      for (var room = 0; room < 3; room++)
        (centre: IVec3(site.x - 12 + room * 12, floor + 1, site.z), half: room == 2 ? 6 : 4),
    ];
    return DungeonPlan._(floor, rooms, [
      if (dungeon.spawner != null)
        for (final r in rooms.take(2)) r.centre + const IVec3(0, 0, 2),
    ], dungeon.chest == null ? null : rooms.last.centre);
  }

  /// The world y of the bricks under every room; one stands at [floor] + 1.
  final int floor;

  /// The three rooms, west to east: two guard rooms, then the larger last
  /// one. A room's [DungeonRoom.centre] is the cell over its floor in its
  /// middle.
  final List<DungeonRoom> rooms;

  /// The cells of the guard rooms' spawner blocks, none when the dungeon has
  /// no spawner.
  final List<IVec3> spawners;

  /// The cell of the last room's chest, in its middle, or null when the
  /// dungeon has no chest.
  final IVec3? chest;
}
