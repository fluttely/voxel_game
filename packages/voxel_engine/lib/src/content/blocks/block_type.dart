import 'package:voxel_engine/core.dart';

/// One block of a game, named by string. The engine sees it through the
/// [VoxelBlockTable] a `BlockRegistry` projects; everything else here is the
/// game's (hardness, tools, drops, tags).
///
/// A game with more to say about its blocks subclasses this and keeps a
/// `BlockRegistry<ItsType>`.
class BlockType {
  /// A block named [id] of colour [color] (`0xRRGGBB`).
  const BlockType(
    this.id, {
    required int color,
    this._name,
    this.alpha = 1.0,
    this.shape = BlockShape.cube,
    this.solid = true,
    bool? opaque,
    this.hardness = 1.0,
    this.tool,
    this.tier = 0,
    this.drop,
    this.light = 0,
    this.speed = 1.0,
    this.tags = const {},
  }) : r = ((color >> 16) & 0xFF) / 255.0,
       g = ((color >> 8) & 0xFF) / 255.0,
       b = (color & 0xFF) / 255.0,
       opaque = opaque ?? (solid && alpha >= 1.0 && shape == BlockShape.cube),
       liquid = null,
       liquidSource = false;

  /// A block of linear rgb [r], [g], [b] (0..1), for a game that keeps its
  /// palette as floats.
  const BlockType.rgb(
    this.id,
    this.r,
    this.g,
    this.b, {
    this._name,
    this.alpha = 1.0,
    this.shape = BlockShape.cube,
    this.solid = true,
    bool? opaque,
    this.hardness = 1.0,
    this.tool,
    this.tier = 0,
    this.drop,
    this.light = 0,
    this.speed = 1.0,
    this.tags = const {},
    this.liquid,
    this.liquidSource = true,
  }) : opaque = opaque ?? (solid && alpha >= 1.0 && shape == BlockShape.cube);

  /// A liquid of [kind] (default: its own id). A source ([source] true) feeds
  /// the flow; its flowing form is another block of the same kind with
  /// [source] false. Liquids are never solid, opaque or mined.
  const BlockType.liquid(
    this.id, {
    required int color,
    this._name,
    String? kind,
    bool source = true,
    this.alpha = 0.6,
    this.light = 0,
    this.speed = 1.0,
    this.tags = const {},
  }) : r = ((color >> 16) & 0xFF) / 255.0,
       g = ((color >> 8) & 0xFF) / 255.0,
       b = (color & 0xFF) / 255.0,
       shape = BlockShape.liquid,
       solid = false,
       opaque = false,
       hardness = -1,
       tool = null,
       tier = 0,
       drop = '',
       liquid = kind ?? id,
       liquidSource = source;

  /// The id: what saves, recipes and world specs name it by.
  final String id;

  final String? _name;

  /// The name a player reads; by default the id in title case
  /// (`oak_log` → `Oak Log`).
  String get name => _name ?? id.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  /// Linear colour, 0..1.
  final double r, g, b;

  /// Opacity, 0..1.
  final double alpha;

  /// How the mesher draws it and the physics collide with it.
  final BlockShape shape;

  /// Stops a body.
  final bool solid;

  /// Hides the faces behind it and stops light. By default: a solid, fully
  /// opaque cube.
  final bool opaque;

  /// Seconds to break by hand; 0 breaks at once, -1 never.
  final double hardness;

  /// The tool that mines it at speed (`'pickaxe'`), or null for none.
  final String? tool;

  /// The lowest tool tier that gets a drop from it; 0 for any.
  final int tier;

  /// The item it drops: null for itself, `''` for nothing.
  final String? drop;

  /// Light emitted, 0..15.
  final int light;

  /// How it scales a walker's speed standing on it (soul sand 0.5).
  final double speed;

  /// Free labels a game queries by (`'plant'`, `'wood'`, `'rail'`).
  final Set<String> tags;

  /// The liquid kind, or null for a block that is not a liquid.
  final String? liquid;

  /// A liquid source rather than its flowing form.
  final bool liquidSource;

  /// Whether this is a liquid.
  bool get isLiquid => liquid != null;
}
