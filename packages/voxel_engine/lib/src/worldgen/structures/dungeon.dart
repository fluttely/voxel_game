import 'package:voxel_engine/core.dart';

import '../spec/structure.dart';
import '../spec/structure_site.dart';
import 'dungeon_plan.dart';

/// Three rooms in a row under the ground, joined by corridors, a ladder shaft
/// up from the first: two guard rooms with a [spawner] each, and a larger
/// last room with the [chest], a [relic] and a [treasure] block. Every wall,
/// floor and ceiling is [walls], one brick in four [mossy]; two [light]s a
/// room. The rooms lie along x, the site in the middle one, [depth] to
/// [depth] + 13 blocks under the surface (never under y 8). Where each part
/// lies is its [DungeonPlan], which a game reads too.
class Dungeon extends Structure {
  /// A dungeon of these blocks; every one left null is left out.
  const Dungeon({
    required this.walls,
    required this.ladder,
    this.mossy,
    this.light,
    this.spawner,
    this.chest,
    this.relic,
    this.treasure,
    this.depth = 14,
  }) : assert(depth > 0);

  /// The bricks.
  final String walls;

  /// The shaft's ladder.
  final String ladder;

  /// One brick in four, or null for [walls] all through.
  final String? mossy;

  /// A light block, two in each room.
  final String? light;

  /// A block in the middle of each guard room.
  final String? spawner;

  /// The last room's chest.
  final String? chest;

  /// A block beside the chest (bones).
  final String? relic;

  /// A block in the last room's corner (gold).
  final String? treasure;

  @override
  final int depth;

  @override
  int get radius => 19;

  @override
  Set<String> get blockNames => {walls, ladder, ?mossy, ?light, ?spawner, ?chest, ?relic, ?treasure};

  @override
  void build(StructureSite site) {
    final plan = DungeonPlan.of(this, site.placed, site.roll);
    // Site-relative, as the drawing goes; the plan's cells are the world's.
    final floor = plan.floor - site.y;
    void putCell(IVec3 cell, String name) => site.put(cell.x - site.x, cell.y - site.y, cell.z - site.z, name);
    for (var room = 0; room < 3; room++) {
      final (:centre, :half) = plan.rooms[room];
      final rx = centre.x - site.x;
      for (var y = 0; y <= half; y++) {
        for (var z = -half; z <= half; z++) {
          for (var x = rx - half; x <= rx + half; x++) {
            final wall = x == rx - half || x == rx + half || z == -half || z == half || y == 0 || y == half;
            site.put(x, floor + y, z, wall ? _brick(site, x, floor + y, z) : 'air');
          }
        }
      }
      final light = this.light;
      if (light != null) {
        site.put(rx - half + 1, floor + 1, -half + 1, light);
        site.put(rx + half - 1, floor + 1, half - 1, light);
      }
      if (room < 2) {
        final spawner = this.spawner;
        if (spawner != null) putCell(plan.spawners[room], spawner);
        // The corridor to the next room, a brick shell around a 1 x 2 way.
        for (var x = rx + half; x <= rx + 8; x++) {
          site.put(x, floor + 1, 0, 'air');
          site.put(x, floor + 2, 0, 'air');
          site.put(x, floor, 0, walls);
          site.put(x, floor + 3, 0, walls);
          for (var y = 1; y <= 2; y++) {
            site.put(x, floor + y, -1, walls);
            site.put(x, floor + y, 1, walls);
          }
        }
      } else {
        final chest = plan.chest;
        if (chest != null) putCell(chest, this.chest!);
        if (relic != null) site.put(rx + 2, floor + 1, -2, relic!);
        if (treasure != null) site.put(rx - 3, floor + 1, 3, treasure!);
      }
    }
    // The shaft up from the first room: a ladder on a brick back, open at the top.
    final top = site.surfaceAt(-15, -3);
    for (var y = floor + 1; y <= top; y++) {
      site.put(-15, y, -3, ladder);
      site.put(-15, y, -4, y < top - 1 ? walls : 'air');
    }
  }

  String _brick(StructureSite site, int x, int y, int z) {
    final mossy = this.mossy;
    return mossy != null && site.hashAt(x, y, z) % 4 == 0 ? mossy : walls;
  }
}
