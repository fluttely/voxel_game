import 'dart:math' as math;

import 'package:voxel_engine/content.dart';

/// What the stores a structure was generated with hold
/// (`VoxelGameSpec.structureLoot`), in place of their block's own
/// `Storage.loot`: [table] rolled once a store, then [bonus] once.
///
/// ```dart
/// structureLoot: {
///   'temple': StructureLoot(
///     LootTable([LootEntry('gold_ingot', 2, 6, 1.0), LootEntry('diamond', 1, 2, 0.6)]),
///     bonus: LootBonus(['iron_sword', 'bow']),
///   ),
/// },
/// ```
class StructureLoot {
  /// A store's [table], and a [bonus] roll after it.
  const StructureLoot(this.table, {this.bonus});

  /// What a store holds, rolled once.
  final LootTable table;

  /// One more stack of an item of its own, or null for none.
  final LootBonus? bonus;
}

/// A roll for one prize: in [chance] of the stores one of [items], with a
/// bonus from [min] to [max] (`ItemStack.bonus`: what a weapon adds to its
/// blows, what an item's row shows beside its damage).
class LootBonus {
  /// One of [items] in [chance] of the rolls, its bonus [min]..[max].
  const LootBonus(this.items, {this.chance = 0.45, this.min = 1, this.max = 6})
    : assert(chance >= 0.0 && chance <= 1.0),
      assert(min >= 1 && min <= max);

  /// The prizes, one picked evenly.
  final List<String> items;

  /// The share of rolls that give one.
  final double chance;

  /// The smallest bonus.
  final int min;

  /// The largest bonus.
  final int max;

  /// One roll with [rng]: a stack of one, or null.
  ItemStack? roll(math.Random rng) {
    if (rng.nextDouble() >= chance) return null;
    final id = items[rng.nextInt(items.length)];
    return ItemStack(id, 1, bonus: min + rng.nextInt(max - min + 1));
  }
}
