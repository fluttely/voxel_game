import 'package:voxel_engine/core.dart';

import 'block_type.dart';

/// A game's blocks, numbered in the order given. **The number is the save
/// contract:** a chunk stores one byte per cell, so blocks are appended,
/// never reordered or removed. Entry 0 is air.
class BlockRegistry<T extends BlockType> {
  /// [types] with air first; at most 256. Throws [ArgumentError] on a
  /// duplicate id or an air that is not id 0.
  BlockRegistry(List<T> types) : types = List<T>.unmodifiable(types) {
    if (types.isEmpty || types.first.solid || types.first.shape != BlockShape.cube) {
      throw ArgumentError('block 0 must be air (not solid, a cube shape)');
    }
    if (types.length > 256) throw ArgumentError('at most 256 blocks fit a byte: ${types.length}');
    for (var i = 0; i < types.length; i++) {
      final id = types[i].id;
      if (_index.containsKey(id)) throw ArgumentError('duplicate block id: $id');
      _index[id] = i;
      final kind = types[i].liquid;
      if (kind != null && !liquidKinds.contains(kind)) liquidKinds.add(kind);
    }
    table = VoxelBlockTable([
      for (final t in types)
        VoxelBlockDef(
          shape: t.shape,
          solid: t.solid,
          opaque: t.opaque,
          r: t.r,
          g: t.g,
          b: t.b,
          a: t.alpha,
          emission: t.light,
          liquidKind: t.liquid == null ? VoxelBlockDef.noLiquid : liquidKinds.indexOf(t.liquid!),
          liquidSource: t.liquid != null && t.liquidSource,
        ),
    ]);
  }

  /// Air's number.
  static const int air = 0;

  /// Every block, by number.
  final List<T> types;

  final Map<String, int> _index = {};

  /// The liquid kinds, numbered in the order they first appear: the kind
  /// index the engine's [VoxelBlockTable] and `LiquidFlow` use.
  final List<String> liquidKinds = [];

  /// The engine's view: shape, solidity, light, colour and liquid kind per
  /// number.
  late final VoxelBlockTable table;

  /// How many blocks.
  int get count => types.length;

  /// Block [id]'s number; throws [ArgumentError] for an unknown id.
  int indexOf(String id) {
    final i = _index[id];
    if (i == null) throw ArgumentError.value(id, 'id', 'unknown block');
    return i;
  }

  /// Whether a block [id] exists.
  bool has(String id) => _index.containsKey(id);

  /// Block number [index].
  T operator [](int index) => types[index];

  /// The id of block number [index].
  String idOf(int index) => types[index].id;

  /// Every id to its number: what a `WorldGenSpec` compiles against.
  Map<String, int> get ids => Map<String, int>.unmodifiable(_index);

  /// The item block [index] drops, or `''` for nothing.
  String dropOf(int index) => types[index].drop ?? types[index].id;

  /// Whether another block may be placed into block [index]: air, plants
  /// (cross and flower shapes) and liquids.
  bool isReplaceable(int index) {
    final s = types[index].shape;
    return index == air || s == BlockShape.cross || s == BlockShape.flower || s == BlockShape.liquid;
  }

  /// Whether block [index] carries [tag].
  bool hasTag(int index, String tag) => types[index].tags.contains(tag);

  /// The numbers of every block carrying [tag].
  List<int> withTag(String tag) => [
    for (var i = 0; i < types.length; i++)
      if (types[i].tags.contains(tag)) i,
  ];

  /// The liquid kind name of block [index], or null.
  String? liquidOf(int index) => types[index].liquid;

  /// The flowing form of liquid [kind]: its block that is not a source.
  /// Throws [StateError] when the kind has none.
  int flowingOf(String kind) {
    for (var i = 0; i < types.length; i++) {
      if (types[i].liquid == kind && !types[i].liquidSource) return i;
    }
    throw StateError('liquid "$kind" has no flowing form');
  }

  /// A path policy: never into the liquids of [avoidLiquids], a floor costing
  /// its inverse walking speed.
  PathCosts pathCosts({Set<String> avoidLiquids = const {}}) =>
      PathCosts(avoid: (b) => avoidLiquids.contains(types[b].liquid), floorCost: (b) => 1.0 / types[b].speed);
}
