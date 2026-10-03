import 'package:voxel_engine/core.dart';

import 'item_grip.dart';

/// What an item looks like wherever it is drawn: in the hand, held by a body,
/// lying on the ground, in a slot. One of the [StockItemShape]s painted in the
/// item's colours, or a [CustomItemShape] of the game's own voxels.
///
/// An item that declares none takes one from its row (`ItemModel.shapeOf`):
/// a block's item its block, a tool its tool's, a launcher a bow, food a
/// lump, armour a tunic, a bucket a pail, anything else a gem.
sealed class ItemShape {
  /// The metres of one voxel of every stock shape: a block's item is eight of
  /// them a side, a pickaxe twelve tall.
  static const double voxelSize = 0.045;

  /// The item's block as the world draws it: a cube, a slab, stairs, a torch,
  /// a sprout, a flower, a door, a fence, a ladder, a rail, a wire.
  static const ItemShape block = StockItemShape.block;

  /// A pickaxe: a shaft and a curved head across it.
  static const ItemShape pickaxe = StockItemShape.pickaxe;

  /// An axe: a shaft and a blade to one side.
  static const ItemShape axe = StockItemShape.axe;

  /// A shovel: a shaft and a spade.
  static const ItemShape shovel = StockItemShape.shovel;

  /// A hoe: a shaft and a blade bent off it.
  static const ItemShape hoe = StockItemShape.hoe;

  /// A sword: a grip, a guard and a blade.
  static const ItemShape sword = StockItemShape.sword;

  /// A bow, strung.
  static const ItemShape bow = StockItemShape.bow;

  /// Shears: two blades crossed over two rings.
  static const ItemShape shears = StockItemShape.shears;

  /// A round lump: food.
  static const ItemShape lump = StockItemShape.lump;

  /// A small cut gem: a material.
  static const ItemShape gem = StockItemShape.gem;

  /// A helmet.
  static const ItemShape cap = StockItemShape.cap;

  /// A chest piece.
  static const ItemShape tunic = StockItemShape.tunic;

  /// A pail with a handle, the liquid it holds in it when full.
  static const ItemShape pail = StockItemShape.pail;
}

/// The kit's shapes, painted in the item's colours. Reach them through
/// [ItemShape]'s constants (`ItemShape.pickaxe`).
enum StockItemShape implements ItemShape {
  /// See [ItemShape.block].
  block,

  /// See [ItemShape.pickaxe].
  pickaxe,

  /// See [ItemShape.axe].
  axe,

  /// See [ItemShape.shovel].
  shovel,

  /// See [ItemShape.hoe].
  hoe,

  /// See [ItemShape.sword].
  sword,

  /// See [ItemShape.bow].
  bow,

  /// See [ItemShape.shears].
  shears,

  /// See [ItemShape.lump].
  lump,

  /// See [ItemShape.gem].
  gem,

  /// See [ItemShape.cap].
  cap,

  /// See [ItemShape.tunic].
  tunic,

  /// See [ItemShape.pail].
  pail,
}

/// A game's own shape: [boxes] of voxels, each filled from its first corner
/// to its second (inclusive) in a `0xRRGGBB` colour, a later box painting over
/// an earlier one; held by the voxel [hold] as [grip] says, each voxel [scale]
/// metres. A flat piece is drawn in the XY plane, standing up +Y from [hold].
final class CustomItemShape implements ItemShape {
  /// A shape of [boxes], held by [hold].
  const CustomItemShape(this.boxes, {required this.grip, this.hold = IVec3.zero, this.scale = ItemShape.voxelSize});

  /// (from, to, colour), painted in order.
  final List<(IVec3, IVec3, int)> boxes;

  /// How it is held.
  final ItemGrip grip;

  /// The voxel it is held by: the model stands on the middle of its floor.
  final IVec3 hold;

  /// Metres a voxel.
  final double scale;
}
