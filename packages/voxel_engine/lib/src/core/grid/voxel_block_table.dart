import 'dart:typed_data';

import '../mesh/chunk_mesher.dart';
import 'block_shape.dart';

/// What the engine needs to know about one block id: how it is drawn, whether
/// it stops a body or light, the light it gives, and whether it is a liquid.
/// Names, drops, tools and every other gameplay fact stay with the game.
class VoxelBlockDef {
  /// One block's engine facts. [r], [g], [b] and [a] are linear, 0..1.
  const VoxelBlockDef({
    required this.shape,
    required this.solid,
    required this.opaque,
    required this.r,
    required this.g,
    required this.b,
    this.a = 1.0,
    this.emission = 0,
    this.liquidKind = noLiquid,
    this.liquidSource = false,
  });

  /// [liquidKind] of a block that is not a liquid.
  static const int noLiquid = -1;

  /// How it is drawn, and its collision boxes when [solid].
  final BlockShape shape;

  /// Stops a body.
  final bool solid;

  /// Occludes faces and stops light.
  final bool opaque;

  /// Linear colour; [a] below 1 draws on the transparent surface.
  final double r, g, b, a;

  /// 0..15 emitted light.
  final int emission;

  /// The game's index of the liquid this block is (water, lava, ...), or
  /// [noLiquid]. A source and its flowing form share one kind.
  final int liquidKind;

  /// A liquid source rather than its flowing form.
  final bool liquidSource;
}

/// The block ids of one game, indexed by the byte a chunk stores. Id 0 is air.
/// Built once from the game's definitions; the typed arrays are what a mesher
/// on a worker isolate is handed.
class VoxelBlockTable {
  /// The table of [defs], where `defs[i]` is block id i. Throws an
  /// [ArgumentError] for more than 256 blocks, a block 0 that is not air, an
  /// emission outside 0..15, or a liquid source with no liquid kind.
  VoxelBlockTable(List<VoxelBlockDef> defs)
    : _defs = List.unmodifiable(defs),
      _boxes = List.unmodifiable([for (final d in defs) collisionBoxesOf(d.shape, solid: d.solid)]),
      palette = Float32List(defs.length * 4),
      shapes = Uint8List.fromList([for (final d in defs) d.shape.index]),
      opaque = Uint8List.fromList([for (final d in defs) d.opaque ? 1 : 0]),
      emission = Uint8List.fromList([for (final d in defs) d.emission]) {
    if (defs.isEmpty || defs.length > 256) {
      throw ArgumentError.value(defs.length, 'defs', 'a chunk stores one byte per cell: 1..256 blocks');
    }
    final first = defs[air];
    if (first.solid || first.opaque || first.emission != 0 || first.liquidKind != VoxelBlockDef.noLiquid) {
      throw ArgumentError('block 0 is air: not solid, not opaque, no light, no liquid');
    }
    for (var i = 0; i < defs.length; i++) {
      final d = defs[i];
      if (d.emission < 0 || d.emission > 15) {
        throw ArgumentError.value(d.emission, 'defs[$i].emission', 'light is 0..15');
      }
      if (d.liquidSource && d.liquidKind == VoxelBlockDef.noLiquid) {
        throw ArgumentError('defs[$i] is a liquid source with no liquid kind');
      }
      palette
        ..[i * 4] = d.r
        ..[i * 4 + 1] = d.g
        ..[i * 4 + 2] = d.b
        ..[i * 4 + 3] = d.a;
    }
  }

  /// The id every empty cell holds.
  static const int air = 0;

  final List<VoxelBlockDef> _defs;
  final List<List<CollisionBox>> _boxes;

  /// Four linear floats (rgba) per id.
  final Float32List palette;

  /// [BlockShape.index] per id.
  final Uint8List shapes;

  /// 1 where the id occludes faces and light.
  final Uint8List opaque;

  /// 0..15 per id.
  final Uint8List emission;

  /// The number of block ids.
  int get count => _defs.length;

  /// The definition of [id].
  VoxelBlockDef def(int id) => _defs[id];

  /// [VoxelBlockDef.shape] of [id].
  BlockShape shapeOf(int id) => _defs[id].shape;

  /// [VoxelBlockDef.solid] of [id].
  bool isSolid(int id) => _defs[id].solid;

  /// [VoxelBlockDef.opaque] of [id].
  bool isOpaque(int id) => _defs[id].opaque;

  /// [VoxelBlockDef.emission] of [id].
  int emissionOf(int id) => _defs[id].emission;

  /// The boxes a body collides with, in the block's own 0..1 space, from the
  /// shape alone (a fence's lone post, no ladder; a body asks
  /// [collisionBoxesAt], which reads their neighbours).
  /// Shared: never mutate.
  List<CollisionBox> collisionBoxes(int id) => _boxes[id];

  /// Whether [id] is a liquid, source or flowing.
  bool isLiquid(int id) => _defs[id].liquidKind != VoxelBlockDef.noLiquid;

  /// [VoxelBlockDef.liquidKind] of [id].
  int liquidKind(int id) => _defs[id].liquidKind;

  /// [VoxelBlockDef.liquidSource] of [id].
  bool isLiquidSource(int id) => _defs[id].liquidSource;

  /// A mesher reading this table.
  ChunkMesher mesher({bool lighting = true}) =>
      ChunkMesher(palette: palette, shape: shapes, opaque: opaque, emission: emission, lighting: lighting);
}
