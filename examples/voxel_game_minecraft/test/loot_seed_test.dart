import 'dart:math' as math;

import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/entities/mob.dart';
import 'package:voxel_game_minecraft/src/game/loot.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chest loot, chest-minecart cargo and villager offers are seeded by an
/// explicit integer hash of (world seed, x, y, z), never by Dart's per-process
/// `hashCode`, so a chest holds the same items after a restart and on every peer.
void main() {
  test('the loot seed of a cell is a fixed constant, independent of the process', () {
    const at = IVec3(12, 40, -7);
    expect(LootTables.seedFor(at, 42), 1205562705);
    expect(LootTables.seedFor(const IVec3(100, 2033, 5), 1337), 141467985);
    expect(LootTables.seedFor(at, 42), isNot(LootTables.seedFor(at, 43)));
    expect(LootTables.seedFor(at, 42), isNot(LootTables.seedFor(const IVec3(12, 41, -7), 42)));
    // Non-negative, so a seed never depends on how an int's sign bits fold.
    expect(LootTables.seedFor(const IVec3(-30000, 250, -30000), -99), greaterThanOrEqualTo(0));
    // The villager offers seed through the same hash.
    expect(Mob.traderSeed(at, 42), LootTables.seedFor(at, 42));
  });

  test('the same cell rolls the same chest in two separate Random constructions', () {
    const at = IVec3(12, 40, -7);
    final seed = LootTables.seedFor(at, 42);
    expect(math.Random(seed).nextDouble(), 0.003025999045451755);
    for (final table in LootTables.tables.keys) {
      final a = LootTables.roll(table, math.Random(LootTables.seedFor(at, 42)));
      final b = LootTables.roll(table, math.Random(LootTables.seedFor(const IVec3(12, 40, -7), 42)));
      expect(a, b, reason: table);
    }
  });
}
