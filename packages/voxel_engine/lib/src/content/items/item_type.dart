import 'armor.dart';
import 'bucket.dart';
import 'food.dart';
import 'glider.dart';
import 'item_shape.dart';

/// One item of a game. A block's item names that block in [block]; one that
/// is eaten says what it does in [food], one that is worn in [armor], one
/// that carries a liquid in [bucket], one that glides in [glider]. What it looks like is its [shape].
///
/// A game with more to say about its items subclasses this and keeps an
/// `ItemRegistry<ItsType>`.
class ItemType {
  /// An item named [id] of colour [color] (`0xRRGGBB`).
  const ItemType(
    this.id, {
    required int color,
    this._name,
    this.block,
    this.stack = 64,
    this.tool,
    this.tier = 0,
    this.damage = 1,
    this.durability = 0,
    this.food,
    this.armor,
    this.bucket,
    this.glider,
    this.shape,
    this.tags = const {},
  }) : r = ((color >> 16) & 0xFF) / 255.0,
       g = ((color >> 8) & 0xFF) / 255.0,
       b = (color & 0xFF) / 255.0;

  /// An item of linear rgb [r], [g], [b] (0..1).
  const ItemType.rgb(
    this.id,
    this.r,
    this.g,
    this.b, {
    this._name,
    this.block,
    this.stack = 64,
    this.tool,
    this.tier = 0,
    this.damage = 1,
    this.durability = 0,
    this.food,
    this.armor,
    this.bucket,
    this.glider,
    this.shape,
    this.tags = const {},
  });

  /// The id: what inventories, recipes and loot name it by.
  final String id;

  final String? _name;

  /// The name a player reads; by default the id in title case.
  String get name => _name ?? id.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  /// Linear colour, 0..1.
  final double r, g, b;

  /// The block it places, or null for an item that places nothing.
  final String? block;

  /// How many fit one inventory slot.
  final int stack;

  /// The tool it is (`'pickaxe'`), or null.
  final String? tool;

  /// Its tool tier: 0 hand, then up (wood 1, stone 2, iron 3, diamond 4 in a
  /// classic block sandbox).
  final int tier;

  /// Melee damage.
  final int damage;

  /// Uses before it breaks; 0 for an item that never wears.
  final int durability;

  /// What eating it does, or null for an item that is not eaten.
  final Food? food;

  /// How it is worn, or null for an item that is not.
  final Armor? armor;

  /// What it does with a liquid, or null for an item that is not a bucket.
  final Bucket? bucket;

  /// How it glides, carried in the bag, or null for an item that does not.
  final Glider? glider;

  /// What it looks like in the hand, on the ground and in a slot; null takes
  /// one from the rest of the row (`ItemModel.shapeOf`).
  final ItemShape? shape;

  /// Free labels a game queries by.
  final Set<String> tags;
}
