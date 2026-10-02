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
/// order, or one of them ([LootTable.oneOf]).
class LootTable {
  /// A table of [entries], each rolled by its own chance.
  const LootTable(this.entries) : oneOf = false;

  /// A table that gives one of its [entries] or nothing: each entry's
  /// [LootEntry.chance] is its slice of one roll, in table order, and what
  /// the slices leave (1 less their sum) gives nothing. The slices sum to 1
  /// at most ([check]).
  const LootTable.oneOf(this.entries) : oneOf = true;

  /// The rows.
  final List<LootEntry> entries;

  /// Whether a roll gives one entry at most ([LootTable.oneOf]) rather than
  /// each by its own chance.
  final bool oneOf;

  /// Throws [ArgumentError] for a [oneOf] table whose slices sum over 1. A
  /// table of entries rolled each by its own chance has nothing to check.
  void check() {
    if (!oneOf) return;
    final sum = entries.fold(0.0, (s, e) => s + e.chance);
    if (sum > 1.0 + 1e-9) throw ArgumentError.value(sum, 'entries', 'one-of chances sum over 1');
  }

  /// The stacks of one roll with [rng], in table order: of a [oneOf] table,
  /// one stack or none (and it [check]s first).
  List<({String id, int count})> roll(math.Random rng) {
    if (oneOf) return _rollOne(rng);
    final out = <({String id, int count})>[];
    for (final e in entries) {
      if (rng.nextDouble() >= e.chance) continue;
      final n = e.min + rng.nextInt(e.max - e.min + 1);
      if (n > 0) out.add((id: e.item, count: n));
    }
    return out;
  }

  List<({String id, int count})> _rollOne(math.Random rng) {
    check();
    var r = rng.nextDouble();
    for (final e in entries) {
      if (r < e.chance) {
        final n = e.min + rng.nextInt(e.max - e.min + 1);
        return n > 0 ? [(id: e.item, count: n)] : const [];
      }
      r -= e.chance;
    }
    return const [];
  }

  /// A seed for the loot at [at] in a world of [worldSeed]: an explicit hash,
  /// the same in every process and on every peer (Dart's `hashCode` is seeded
  /// per run), so the same chest holds the same things for everyone.
  static int seedFor(IVec3 at, int worldSeed) =>
      ((at.x * 73856093) ^ (at.y * 19349663) ^ (at.z * 83492791) ^ worldSeed) & 0x7FFFFFFF;
}
