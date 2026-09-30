import 'package:voxel_engine/core.dart';

import 'block_type.dart';

/// A game's blocks, numbered in the order given. **The number is the save
/// contract:** a chunk stores one byte per cell, so blocks are appended,
/// never reordered or removed. Entry 0 is air.
class BlockRegistry<T extends BlockType> {
  /// [types] with air first; at most 256. Throws [ArgumentError] on a
  /// duplicate id, an air that is not id 0, or a block that names one that
  /// does not exist (what it leans on, its wall form).
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
    for (final t in types) {
      void known(String? name, String what) {
        if (name != null && !_index.containsKey(name)) throw ArgumentError.value(name, t.id, '$what names no block');
      }

      known(t.onWall, 'its wall form');
      for (final on in t.support?.on ?? const <String>{}) {
        known(on, 'what it stands on');
      }
    }
    _standsOn = [
      for (final t in types) {for (final on in t.support?.on ?? const <String>{}) _index[on]!},
    ];
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

  late final List<Set<int>> _standsOn;

  /// Whether block [id] would stay at [cell] of [world]: it has no `support`,
  /// or what it leans on is there (`Support.below`: a solid block below, one
  /// of its `on` when it names some; `Support.side`: an opaque block on one of
  /// the four sides).
  bool stands(VoxelQuery world, IVec3 cell, int id) {
    final support = types[id].support;
    if (support == null) return true;
    if (support.side) {
      for (final s in IVec3.sides) {
        if (table.isOpaque(world.getBlockXYZ(cell.x + s.x, cell.y, cell.z + s.z))) return true;
      }
      return false;
    }
    final below = world.getBlockXYZ(cell.x, cell.y - 1, cell.z);
    final on = _standsOn[id];
    return on.isEmpty ? table.isSolid(below) : on.contains(below);
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
