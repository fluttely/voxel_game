import 'dart:math' as math;

import 'package:voxel_engine/core.dart';

import '../spec/spec_generator.dart';
import 'mine.dart';

/// Where the parts of a [Mine] lie, in world cells: its corridor at [floor],
/// running [length] blocks along +x from beside its site, the [chest] at its
/// end and the [spawner] three before it, the one mine in three that has
/// one. The mine draws from it, and a game finds the same cells by it
/// without reading the world.
class MinePlan {
  const MinePlan._(this.floor, this.length, this.end, this.chest, this.spawner);

  /// The plan of [mine] at [site], whose rolls are [roll]: the drawing's
  /// `StructureSite.roll`, or a game's `SpecGenerator.rollOf(site)`.
  factory MinePlan.of(Mine mine, PlacedStructure site, int Function(int salt) roll) {
    final h = roll(41);
    final length = mine.minLength + h % (mine.maxLength - mine.minLength + 1);
    final floor = math.min(mine.floorY, site.y - 8);
    final end = IVec3(site.x + length, floor + 1, site.z);
    final guarded = mine.spawner != null && (h >> 8) % 3 == 0;
    return MinePlan._(floor, length, end, mine.chest == null ? null : end, guarded ? end - const IVec3(3, 0, 0) : null);
  }

  /// The world y of the corridor's floor; one stands at [floor] + 1.
  final int floor;

  /// How far the corridor runs, from the cell past the shaft to [end].
  final int length;

  /// The cell over the corridor's floor at its far end.
  final IVec3 end;

  /// The cell of the chest at [end], or null when the mine has no chest.
  final IVec3? chest;

  /// The cell of the spawner block three before [end], or null in a mine
  /// without one.
  final IVec3? spawner;
}
