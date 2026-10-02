import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import '../blocks/block_registry.dart';
import '../blocks/block_type.dart';
import 'item_grip.dart';
import 'item_registry.dart';
import 'item_shape.dart';
import 'item_type.dart';

typedef _Rgb = (double, double, double);

/// What a stock look is built from: the shape, the block's form for a block's
/// item, the main colour and a second one (a full pail's liquid).
typedef _Look = (StockItemShape, BlockShape?, _Rgb, _Rgb?);

/// An item's look, built: the [voxels] its [ItemShape] paints in its colours,
/// the point it is held by ([origin]), how ([grip]) and the metres of a voxel
/// ([scale]). Built once a look ([of]): two items that look alike are one
/// model, so whatever is made from it (a mesh, an icon) is made once for both.
class ItemModel {
  ItemModel._(this.voxels, this.origin, this.grip, [this.scale = ItemShape.voxelSize]);

  /// The model of [item], whose block (if it places one) is in [blocks] and
  /// whose bucket's items (if it is one) are in [items]: the same object for
  /// every item of the same look. Throws [ArgumentError] for [ItemShape.block]
  /// on an item that places no block.
  factory ItemModel.of(ItemType item, BlockRegistry<BlockType> blocks, ItemRegistry<ItemType> items) {
    switch (shapeOf(item)) {
      case final CustomItemShape shape:
        return _custom[shape] ??= _fromCustom(shape);
      case final StockItemShape shape:
        final look = _lookOf(shape, item, blocks, items);
        return _built[look] ??= _build(look);
    }
  }

  static final Map<_Look, ItemModel> _built = {};
  static final Map<CustomItemShape, ItemModel> _custom = {};

  /// The shape [item] is drawn as: its own [ItemType.shape], or else one read
  /// off its row. Throws [ArgumentError] for a tool the kit has no shape for,
  /// which must declare its own.
  static ItemShape shapeOf(ItemType item) {
    final declared = item.shape;
    if (declared != null) return declared;
    if (item.block != null) return ItemShape.block;
    final tool = item.tool;
    if (tool != null) {
      return switch (tool) {
        'pickaxe' => ItemShape.pickaxe,
        'axe' => ItemShape.axe,
        'shovel' => ItemShape.shovel,
        'hoe' => ItemShape.hoe,
        'sword' => ItemShape.sword,
        _ => throw ArgumentError.value(tool, item.id, 'the kit has no shape for this tool: declare the item\'s shape'),
      };
    }
    if (item.food != null) return ItemShape.lump;
    if (item.armor != null) return ItemShape.tunic;
    if (item.bucket != null) return ItemShape.pail;
    return ItemShape.gem;
  }

  /// {voxel: colour}.
  final Map<IVec3, Vector3> voxels;

  /// The voxel-space point the model's node sits on: where it is held, on the
  /// floor of the model.
  final Vector3 origin;

  /// How it is held.
  final ItemGrip grip;

  /// Metres a voxel.
  final double scale;

  /// The model's bounds in metres, in its node's space.
  Aabb3 bounds() {
    final lo = Vector3.all(double.infinity), hi = Vector3.all(double.negativeInfinity);
    for (final p in voxels.keys) {
      final a = Vector3((p.x - origin.x) * scale, (p.y - origin.y) * scale, (p.z - origin.z) * scale);
      Vector3.min(lo, a, lo);
      Vector3.max(hi, a + Vector3.all(scale), hi);
    }
    return Aabb3.minMax(lo, hi);
  }

  static _Rgb _rgbOf(double r, double g, double b) => (r, g, b);

  static _Look _lookOf(
    StockItemShape shape,
    ItemType item,
    BlockRegistry<BlockType> blocks,
    ItemRegistry<ItemType> items,
  ) {
    if (shape == StockItemShape.block) {
      final id = item.block;
      if (id == null) throw ArgumentError.value(item.id, 'item', 'a block\'s shape on an item that places no block');
      final b = blocks[blocks.indexOf(id)];
      return (shape, b.shape, _rgbOf(b.r, b.g, b.b), null);
    }
    final bucket = item.bucket;
    if (shape == StockItemShape.pail && bucket != null && bucket.isFull) {
      // A full pail is the empty one with its liquid in it.
      final pail = items[bucket.empties!];
      final liquid = blocks[blocks.indexOf(bucket.liquid!)];
      return (shape, null, _rgbOf(pail.r, pail.g, pail.b), _rgbOf(liquid.r, liquid.g, liquid.b));
    }
    return (shape, null, _rgbOf(item.r, item.g, item.b), null);
  }

  static ItemModel _fromCustom(CustomItemShape s) {
    if (s.boxes.isEmpty) throw ArgumentError('a custom item shape needs voxels');
    final v = <IVec3, Vector3>{};
    for (final (from, to, c) in s.boxes) {
      VoxelModel.box(v, from, to, Vector3(((c >> 16) & 0xFF) / 255.0, ((c >> 8) & 0xFF) / 255.0, (c & 0xFF) / 255.0));
    }
    return ItemModel._(v, Vector3(s.hold.x + 0.5, s.hold.y.toDouble(), s.hold.z + 0.5), s.grip, s.scale);
  }

  static final Vector3 _wood = Vector3(0.45, 0.32, 0.18);

  static ItemModel _build(_Look look) {
    final (shape, form, (r, g, b), second) = look;
    final c = Vector3(r, g, b);
    final v = <IVec3, Vector3>{};
    // Tools, weapons and flat pieces are drawn in XY, a shaft up +Y from the
    // grip at the origin and a head across X.
    final grip = Vector3(0.5, 0, 0.5);
    switch (shape) {
      case StockItemShape.block:
        return _block(form!, c);
      case StockItemShape.pickaxe:
        VoxelModel.box(v, IVec3.zero, const IVec3(0, 9, 0), _wood, 0.03);
        VoxelModel.box(v, const IVec3(-3, 9, 0), const IVec3(3, 9, 0), c);
        VoxelModel.box(v, const IVec3(-4, 8, 0), const IVec3(-4, 8, 0), c);
        VoxelModel.box(v, const IVec3(4, 8, 0), const IVec3(4, 8, 0), c);
        return ItemModel._(v, grip, ItemGrip.flat);
      case StockItemShape.axe:
        VoxelModel.box(v, IVec3.zero, const IVec3(0, 9, 0), _wood, 0.03);
        VoxelModel.box(v, const IVec3(1, 7, 0), const IVec3(2, 10, 0), c);
        VoxelModel.box(v, const IVec3(3, 8, 0), const IVec3(3, 10, 0), c);
        return ItemModel._(v, grip, ItemGrip.flat);
      case StockItemShape.shovel:
        VoxelModel.box(v, IVec3.zero, const IVec3(0, 8, 0), _wood, 0.03);
        VoxelModel.box(v, const IVec3(-1, 9, 0), const IVec3(1, 11, 0), c);
        VoxelModel.box(v, const IVec3(0, 12, 0), const IVec3(0, 12, 0), c);
        return ItemModel._(v, grip, ItemGrip.flat);
      case StockItemShape.hoe:
        VoxelModel.box(v, IVec3.zero, const IVec3(0, 10, 0), _wood, 0.03);
        VoxelModel.box(v, const IVec3(-3, 10, 0), const IVec3(-1, 10, 0), c);
        VoxelModel.box(v, const IVec3(-3, 9, 0), const IVec3(-3, 9, 0), c);
        return ItemModel._(v, grip, ItemGrip.flat);
      case StockItemShape.sword:
        VoxelModel.box(v, IVec3.zero, const IVec3(0, 2, 0), _wood, 0.03);
        VoxelModel.box(v, const IVec3(-1, 3, 0), const IVec3(1, 3, 0), Vector3(0.5, 0.5, 0.5));
        VoxelModel.box(v, const IVec3(0, 4, 0), const IVec3(0, 13, 0), c, 0.02);
        return ItemModel._(v, grip, ItemGrip.flat);
      case StockItemShape.bow:
        VoxelModel.box(v, const IVec3(0, -4, 0), const IVec3(0, 4, 0), c);
        VoxelModel.box(v, const IVec3(1, -5, 0), const IVec3(1, -3, 0), c);
        VoxelModel.box(v, const IVec3(1, 3, 0), const IVec3(1, 5, 0), c);
        VoxelModel.box(v, const IVec3(-1, -5, 0), const IVec3(-1, 5, 0), Vector3(0.9, 0.9, 0.85), 0.0);
        return ItemModel._(v, grip, ItemGrip.flat);
      case StockItemShape.lump:
        // A 5-wide cube with its edges filed off.
        VoxelModel.box(v, const IVec3(-2, 1, -1), const IVec3(2, 3, 1), c);
        VoxelModel.box(v, const IVec3(-1, 0, -1), const IVec3(1, 4, 1), c);
        VoxelModel.box(v, const IVec3(-1, 1, -2), const IVec3(1, 3, 2), c);
        return ItemModel._(v, grip, ItemGrip.upright);
      case StockItemShape.gem:
        // Wider at its girdle.
        VoxelModel.box(v, const IVec3(-1, 0, 0), const IVec3(1, 0, 0), c * 0.8);
        VoxelModel.box(v, const IVec3(-2, 1, 0), const IVec3(2, 2, 0), c);
        VoxelModel.box(v, const IVec3(-1, 3, 0), const IVec3(1, 3, 0), c * 1.15);
        VoxelModel.box(v, const IVec3(0, 4, 0), const IVec3(0, 4, 0), c * 1.15);
        return ItemModel._(v, grip, ItemGrip.flat);
      case StockItemShape.cap:
        VoxelModel.box(v, const IVec3(-3, 0, -3), const IVec3(3, 2, 3), c);
        VoxelModel.box(v, const IVec3(-2, 3, -2), const IVec3(2, 3, 2), c);
        VoxelModel.box(v, const IVec3(-3, 0, -4), const IVec3(3, 0, -4), c * 0.75, 0.02);
        return ItemModel._(v, grip, ItemGrip.upright);
      case StockItemShape.tunic:
        // Seen from the front: shoulders, a body and a gap for the neck.
        VoxelModel.box(v, const IVec3(-3, 4, 0), const IVec3(-1, 6, 0), c);
        VoxelModel.box(v, const IVec3(1, 4, 0), const IVec3(3, 6, 0), c);
        VoxelModel.box(v, const IVec3(-2, 0, 0), const IVec3(2, 5, 0), c);
        VoxelModel.box(v, const IVec3(-2, 0, 0), const IVec3(2, 0, 0), c * 0.75, 0.02);
        return ItemModel._(v, grip, ItemGrip.flat);
      case StockItemShape.pail:
        VoxelModel.box(v, const IVec3(-2, 0, -2), const IVec3(2, 1, 2), c);
        VoxelModel.box(v, const IVec3(-3, 2, -3), const IVec3(3, 5, 3), c);
        // Hollow, and filled to below its rim when it holds something.
        for (var x = -2; x <= 2; x++) {
          for (var z = -2; z <= 2; z++) {
            for (var y = 2; y <= 5; y++) {
              v.remove(IVec3(x, y, z));
            }
          }
        }
        if (second case (final lr, final lg, final lb)) {
          VoxelModel.box(v, const IVec3(-2, 2, -2), const IVec3(2, 4, 2), Vector3(lr, lg, lb), 0.03);
        }
        final iron = Vector3(0.35, 0.35, 0.38);
        VoxelModel.box(v, const IVec3(-3, 6, 0), const IVec3(-3, 6, 0), iron);
        VoxelModel.box(v, const IVec3(3, 6, 0), const IVec3(3, 6, 0), iron);
        VoxelModel.box(v, const IVec3(-2, 7, 0), const IVec3(2, 7, 0), iron);
        return ItemModel._(v, grip, ItemGrip.upright);
    }
  }

  /// A block's item: the block as the chunk mesher draws it, eight voxels to
  /// the block's side.
  static ItemModel _block(BlockShape form, Vector3 c) {
    final v = <IVec3, Vector3>{};
    final middle = Vector3(4, 0, 4);
    switch (form) {
      case BlockShape.cube || BlockShape.liquid:
        VoxelModel.box(v, IVec3.zero, const IVec3(7, 7, 7), c, 0.06);
        return ItemModel._(v, middle, ItemGrip.block);
      case BlockShape.slab:
        VoxelModel.box(v, IVec3.zero, const IVec3(7, 3, 7), c, 0.06);
        return ItemModel._(v, middle, ItemGrip.block);
      case BlockShape.stairsN || BlockShape.stairsE || BlockShape.stairsS || BlockShape.stairsW:
        VoxelModel.box(v, IVec3.zero, const IVec3(7, 3, 7), c, 0.06);
        VoxelModel.box(v, const IVec3(0, 4, 0), const IVec3(7, 7, 3), c, 0.06);
        return ItemModel._(v, middle, ItemGrip.block);
      case BlockShape.fence:
        VoxelModel.box(v, const IVec3(3, 0, 3), const IVec3(4, 7, 4), c, 0.04);
        VoxelModel.box(v, const IVec3(0, 2, 3), const IVec3(7, 2, 4), c * 0.9, 0.04);
        VoxelModel.box(v, const IVec3(0, 5, 3), const IVec3(7, 5, 4), c * 0.9, 0.04);
        return ItemModel._(v, middle, ItemGrip.block);
      case BlockShape.cross:
        // The sprout the mesher draws as two crossed sheets, a voxel at a time.
        for (var i = 0; i < 8; i++) {
          final top = 2 + (i * 5 + 3) % 3 + (i > 1 && i < 6 ? 1 : 0);
          VoxelModel.box(v, IVec3(i, 0, i), IVec3(i, 1, i), c * 0.7, 0.04);
          VoxelModel.box(v, IVec3(i, 2, i), IVec3(i, top, i), c, 0.04);
          VoxelModel.box(v, IVec3(i, 0, 7 - i), IVec3(i, 1, 7 - i), c * 0.7, 0.04);
          VoxelModel.box(v, IVec3(i, 2, 7 - i), IVec3(i, top - 1, 7 - i), c, 0.04);
        }
        return ItemModel._(v, middle, ItemGrip.upright);
      case BlockShape.flower:
        VoxelModel.box(v, const IVec3(3, 0, 3), const IVec3(3, 3, 3), Vector3(0.30, 0.55, 0.22), 0.03);
        VoxelModel.box(v, const IVec3(2, 4, 2), const IVec3(4, 4, 4), c, 0.04);
        VoxelModel.box(v, const IVec3(3, 5, 3), const IVec3(3, 5, 3), c * 1.1, 0.0);
        return ItemModel._(v, Vector3(3.5, 0, 3.5), ItemGrip.upright);
      case BlockShape.torch || BlockShape.wallTorch:
        VoxelModel.box(v, const IVec3(3, 0, 3), const IVec3(4, 4, 4), _wood, 0.03);
        VoxelModel.box(v, const IVec3(3, 5, 3), const IVec3(4, 5, 4), c, 0.0);
        return ItemModel._(v, middle, ItemGrip.upright);
      case BlockShape.panelZ || BlockShape.panelX:
        // A door seen from its face, its knob standing out of it.
        VoxelModel.box(v, IVec3.zero, const IVec3(5, 11, 0), c, 0.05);
        VoxelModel.box(v, const IVec3(1, 7, 0), const IVec3(4, 10, 0), c * 0.85, 0.03);
        v[const IVec3(4, 5, -1)] = c * 0.5;
        return ItemModel._(v, Vector3(3, 0, 0.5), ItemGrip.flat);
      case BlockShape.ladder:
        VoxelModel.box(v, IVec3.zero, const IVec3(0, 9, 0), c, 0.03);
        VoxelModel.box(v, const IVec3(5, 0, 0), const IVec3(5, 9, 0), c, 0.03);
        for (final y in const [1, 4, 7]) {
          VoxelModel.box(v, IVec3(1, y, 0), IVec3(4, y, 0), c * 0.85, 0.03);
        }
        return ItemModel._(v, Vector3(3, 0, 0.5), ItemGrip.flat);
      case BlockShape.wire:
        VoxelModel.box(v, const IVec3(1, 0, 3), const IVec3(6, 0, 4), c, 0.04);
        VoxelModel.box(v, const IVec3(3, 0, 1), const IVec3(4, 0, 6), c, 0.04);
        return ItemModel._(v, middle, ItemGrip.block);
      case BlockShape.railNs ||
          BlockShape.railEw ||
          BlockShape.railNe ||
          BlockShape.railNw ||
          BlockShape.railSe ||
          BlockShape.railSw ||
          BlockShape.railSlopeN ||
          BlockShape.railSlopeE ||
          BlockShape.railSlopeS ||
          BlockShape.railSlopeW:
        // A straight piece of track: ties under two bars.
        for (final z in const [0, 3, 6]) {
          VoxelModel.box(v, IVec3(0, 0, z), IVec3(7, 0, z + 1), _wood, 0.04);
        }
        VoxelModel.box(v, const IVec3(1, 1, 0), const IVec3(1, 1, 7), c, 0.02);
        VoxelModel.box(v, const IVec3(6, 1, 0), const IVec3(6, 1, 7), c, 0.02);
        return ItemModel._(v, middle, ItemGrip.block);
    }
  }
}
