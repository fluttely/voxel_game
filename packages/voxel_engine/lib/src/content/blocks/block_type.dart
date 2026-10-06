import 'package:voxel_engine/core.dart';

import '../loot/loot_table.dart';
import 'facing.dart';
import 'growth.dart';
import 'storage.dart';
import 'support.dart';

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
    this.falls = false,
    this.support,
    this.onWall,
    this.loot,
    this.facing,
    this.tall = false,
    this.usedInto,
    this.grows,
    this.turnsWith = const {},
    this.storage,
    this.bed = false,
    this.holdable = true,
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
    this.falls = false,
    this.support,
    this.onWall,
    this.loot,
    this.facing,
    this.tall = false,
    this.usedInto,
    this.grows,
    this.turnsWith = const {},
    this.storage,
    this.bed = false,
    this.holdable = true,
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
       liquidSource = source,
       falls = false,
       support = null,
       onWall = null,
       loot = null,
       facing = null,
       tall = false,
       usedInto = null,
       grows = null,
       turnsWith = const {},
       storage = null,
       bed = false,
       holdable = false;

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

  /// The item it drops: null for itself, `''` for nothing. [loot], when
  /// given, is rolled instead.
  final String? drop;

  /// What it drops when broken, rolled each time (a ripe crop's grain and
  /// seeds); null to drop [drop].
  final LootTable? loot;

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

  /// Falls while the cell below it would take a block (sand, gravel): at
  /// once, to where it lands, when it is placed or what held it goes.
  final bool falls;

  /// What it leans on, or null for a block that stands anywhere. Without it,
  /// it breaks and drops.
  final Support? support;

  /// The block placed instead when a player puts this one against a wall
  /// (a torch becomes a wall torch), or null to place this one there too.
  final String? onWall;

  /// The variants a player's placing chooses from by the way they look
  /// (stairs, a door), or null for a block placed as it is. Its item places
  /// this block, which is one of the variants.
  final Facing? facing;

  /// Two cells high (a door): placed into the cell above as well, broken and
  /// used as one. Both halves are this block.
  final bool tall;

  /// The block a player's use turns it into (a door opens, and its open
  /// state's [usedInto] closes it), or null for a block that is not used.
  final String? usedInto;

  /// How it grows into its next stage (a crop), or null for a block that
  /// does not grow.
  final Growth? grows;

  /// The block it becomes when a player uses a tool of a kind on it, by the
  /// tool kind (`{'hoe': 'farmland'}`: a hoe tills it).
  final Map<String, String> turnsWith;

  /// What it stores (a chest), or null for a block that stores nothing.
  final Storage? storage;

  /// A bed: a player's use sleeps in it at night, and sets where they stand
  /// up after dying.
  final bool bed;

  /// Whether it is an item a player can hold: false for a block only the
  /// world makes, which no bag shows (a portal, an open door, a rail's
  /// curve, a lit lamp), and for a liquid. A block that is not drops
  /// another item, or nothing.
  final bool holdable;
}
