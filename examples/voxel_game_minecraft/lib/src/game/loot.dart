import 'dart:math' as math;

import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';

import '../world/voxel_world.dart';

export 'package:voxel_engine/content.dart' show LootEntry;

/// Stage 23: what a structure's chest holds, one table per structure. Every
/// entry is rolled once: `chance` to appear at all, then `min..max` of it. The
/// rng is seeded by the caller from the chest position, so the same chest gives
/// the same loot to everyone.
class LootTables {
  LootTables._();

  static const Map<String, List<LootEntry>> tables = {
    'temple': [
      LootEntry('gold_ingot', 2, 6, 1.0),
      LootEntry('diamond', 1, 2, 0.6),
      LootEntry('health_potion', 1, 2, 0.7),
      LootEntry('regen_potion', 1, 1, 0.4),
      LootEntry('strength_potion', 1, 1, 0.3),
      LootEntry('magic_dust', 1, 3, 0.5),
      LootEntry('ancient_blade', 1, 1, 0.1),
    ],
    'mine': [
      LootEntry('iron_ingot', 2, 5, 0.9),
      LootEntry('coal', 4, 10, 1.0),
      LootEntry('torch', 3, 8, 0.9),
      LootEntry('bread', 1, 3, 0.7),
      LootEntry('raw_gold', 1, 2, 0.3),
      LootEntry('iron_pickaxe', 1, 1, 0.15),
    ],
    'ruin': [
      LootEntry('wheat_seeds', 2, 6, 0.8),
      LootEntry('bone', 1, 4, 0.9),
      LootEntry('cobblestone', 4, 12, 1.0),
      LootEntry('speed_potion', 1, 1, 0.2),
      LootEntry('antidote', 1, 1, 0.15),
      LootEntry('string', 1, 3, 0.4),
    ],
    'well': [
      LootEntry('raw_fish', 1, 3, 0.9),
      LootEntry('raw_salmon', 1, 1, 0.4),
      LootEntry('glass_bottle', 1, 3, 0.8),
      LootEntry('bucket', 1, 1, 0.2),
    ],
    'dungeon': [
      LootEntry('iron_ingot', 2, 5, 0.8),
      LootEntry('arrow', 6, 14, 0.8),
      LootEntry('gold_ingot', 1, 3, 0.5),
      LootEntry('diamond', 1, 1, 0.3),
      LootEntry('health_potion', 1, 2, 0.6),
      LootEntry('magic_dust', 1, 3, 0.7),
      LootEntry('gem_shard', 1, 2, 0.4),
      LootEntry('glider', 1, 1, 0.15),
    ],
    // Stage 26: what a village hut's chest holds.
    'village': [
      LootEntry('bread', 2, 5, 1.0),
      LootEntry('wheat', 3, 8, 0.8),
      LootEntry('wheat_seeds', 2, 6, 0.7),
      LootEntry('gold_ingot', 1, 2, 0.5),
      LootEntry('leather', 1, 3, 0.5),
      LootEntry('torch', 2, 6, 0.6),
      LootEntry('iron_ingot', 1, 2, 0.3),
    ],
    // Stage 29: the fortress side rooms.
    'fortress': [
      LootEntry('quartz', 3, 8, 1.0),
      LootEntry('gold_ingot', 2, 5, 0.8),
      LootEntry('health_potion', 1, 2, 0.7),
      LootEntry('resistance_potion', 1, 1, 0.4),
      LootEntry('blaze_rod', 1, 3, 0.6),
      LootEntry('glowstone_dust', 2, 6, 0.5),
      LootEntry('diamond', 1, 1, 0.25),
    ],
    'camp': [
      LootEntry('apple', 1, 4, 0.9),
      LootEntry('bread', 1, 3, 0.7),
      LootEntry('arrow', 4, 10, 0.7),
      LootEntry('leather', 1, 3, 0.6),
      LootEntry('torch', 2, 6, 0.6),
      LootEntry('coal', 2, 6, 0.5),
    ],
  };

  /// Structure kind (`TerrainGenerator.struct*`) -> table. Kind 4 (village) has a
  /// chest per hut since stage 26.
  static const Map<int, String> tableByKind = {1: 'dungeon', 2: 'dungeon', 3: 'camp', 4: 'village', 5: 'ruin', 6: 'well', 7: 'mine', 8: 'temple', 9: 'fortress'};

  /// The rng seed for the loot at [at] in a world of [worldSeed]: an explicit
  /// integer hash, the same in every process and on every peer. Dart's
  /// `hashCode` / `Object.hash` are seeded per run, so a chest seeded from
  /// `IVec3.hashCode` held other items after a restart, and a host and its
  /// client could disagree about it. Chests, chest minecarts and villager offers
  /// all seed through here.
  static int seedFor(IVec3 at, int worldSeed) => LootTable.seedFor(at, worldSeed);

  /// The stacks a chest of [table] holds, in table order.
  static List<({String id, int count})> roll(String table, math.Random rng) {
    final rows = tables[table];
    if (rows == null) throw ArgumentError('unknown loot table $table');
    return LootTable(rows).roll(rng);
  }

  /// The table of the structure nearest to [at] (within 48 m), "camp" when no
  /// structure claims it.
  static String tableNear(VoxelWorld world, IVec3 at) {
    final here = VoxelWorld.chunkOf(at);
    var best = 'camp';
    var bestD = 48.0;
    for (var dz = -2; dz < 3; dz++) {
      for (var dx = -2; dx < 3; dx++) {
        for (final s in world.structuresNear((x: here.x + dx, z: here.z + dz))) {
          final table = tableByKind[s.type];
          if (table == null) continue;
          final d = math.sqrt(math.pow(s.x - at.x, 2) + math.pow(s.z - at.z, 2));
          if (d < bestD) {
            bestD = d;
            best = table;
          }
        }
      }
    }
    return best;
  }
}
