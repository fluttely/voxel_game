import '../loot/loot_table.dart';

/// What a block that stores things holds (a chest): its [slots], and the
/// [loot] a generated one is found with. One a player places starts empty.
class Storage {
  /// A store of [slots], found filled by [loot] when the world made it.
  const Storage({this.slots = 27, this.loot}) : assert(slots > 0);

  /// How many stacks it holds.
  final int slots;

  /// What a generated one holds when first looked into, rolled from a seed of
  /// its cell and the world's (`LootTable.seedFor`), so every player finds the
  /// same; null for empty.
  final LootTable? loot;
}
