import 'dart:math' as math;

import 'package:voxel_engine/core.dart';

/// One row of a [LootTable]: [chance] to appear at all, then [min]..[max] of
/// [item].
class LootEntry {
  /// A row.
  const LootEntry(this.item, this.min, this.max, this.chance) : assert(min <= max);

  /// The item.
  final String item;

  /// The fewest.
  final int min;

  /// The most.
  final int max;

  /// The chance to appear, 0..1.
  final double chance;
}

/// What a chest, a mob or a fishing line gives: every entry rolled once, in
/// order.
class LootTable {
  /// A table of [entries].
  const LootTable(this.entries);

  /// The rows.
  final List<LootEntry> entries;

  /// The stacks of one roll with [rng], in table order.
  List<({String id, int count})> roll(math.Random rng) {
    final out = <({String id, int count})>[];
    for (final e in entries) {
      if (rng.nextDouble() >= e.chance) continue;
      final n = e.min + rng.nextInt(e.max - e.min + 1);
      if (n > 0) out.add((id: e.item, count: n));
    }
    return out;
  }

  /// A seed for the loot at [at] in a world of [worldSeed]: an explicit hash,
  /// the same in every process and on every peer (Dart's `hashCode` is seeded
  /// per run), so the same chest holds the same things for everyone.
  static int seedFor(IVec3 at, int worldSeed) =>
      ((at.x * 73856093) ^ (at.y * 19349663) ^ (at.z * 83492791) ^ worldSeed) & 0x7FFFFFFF;
}
