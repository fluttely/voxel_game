import '../blocks/block_registry.dart';
import '../blocks/block_type.dart';
import 'item_type.dart';

/// A game's items by id.
class ItemRegistry<T extends ItemType> {
  /// [types]; throws [ArgumentError] on a duplicate id.
  ItemRegistry(Iterable<T> types) {
    for (final t in types) {
      if (_types.containsKey(t.id)) throw ArgumentError('duplicate item id: ${t.id}');
      _types[t.id] = t;
    }
  }

  final Map<String, T> _types = {};

  /// Every item, in the order given.
  Iterable<T> get all => _types.values;

  /// Whether item [id] exists.
  bool has(String id) => _types.containsKey(id);

  /// Item [id]; throws [ArgumentError] for an unknown one.
  T operator [](String id) {
    final t = _types[id];
    if (t == null) throw ArgumentError.value(id, 'id', 'unknown item');
    return t;
  }

  /// One item per block of [blocks] that a player can hold (not air, not a
  /// liquid), placing that block, for a game whose blocks are all items.
  static List<ItemType> forBlocks(BlockRegistry<BlockType> blocks, {bool Function(BlockType block)? where}) => [
    for (final b in blocks.types.skip(1))
      if (!b.isLiquid && (where == null || where(b))) ItemType.rgb(b.id, b.r, b.g, b.b, name: b.name, block: b.id),
  ];
}
