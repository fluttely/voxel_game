import 'package:test/test.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';

final BlockRegistry<BlockType> _blocks = BlockRegistry(const [
  BlockType('air', color: 0, solid: false, hardness: -1, drop: ''),
  BlockType('stone', color: 0x808080, hardness: 3),
  BlockType('slab', color: 0x808080, shape: BlockShape.slab, hardness: 3),
  BlockType('torch', color: 0xFFD040, shape: BlockShape.torch, solid: false, hardness: 0),
  BlockType('door', color: 0x9A7040, shape: BlockShape.panelZ, hardness: 1),
  BlockType.liquid('water', color: 0x3366CC),
]);

final ItemRegistry<ItemType> _items = ItemRegistry([
  ...ItemRegistry.forBlocks(_blocks),
  const ItemType('pick', color: 0xB08850, tool: 'pickaxe'),
  const ItemType('apple', color: 0xD03A2A, food: Food(hunger: 4)),
  const ItemType('cap', color: 0xE8E8E8, armor: Armor('head', 1)),
  const ItemType('helm', color: 0xE8E8E8, armor: Armor('head', 1), shape: ItemShape.cap),
  const ItemType('bucket', color: 0x8A6A40, bucket: Bucket.empty({'water': 'water_bucket'})),
  const ItemType('water_bucket', color: 0x3366CC, bucket: Bucket.full('water', empties: 'bucket')),
  const ItemType('coal', color: 0x202020),
]);

ItemModel _model(String id) => ItemModel.of(_items[id], _blocks, _items);

void main() {
  test('an item with no shape of its own takes one from its row', () {
    ItemShape shape(String id) => ItemModel.shapeOf(_items[id]);
    expect(shape('stone'), ItemShape.block);
    expect(shape('pick'), ItemShape.pickaxe);
    expect(shape('apple'), ItemShape.lump);
    expect(shape('cap'), ItemShape.tunic);
    expect(shape('helm'), ItemShape.cap, reason: 'declared');
    expect(shape('bucket'), ItemShape.pail);
    expect(shape('coal'), ItemShape.gem);
    expect(
      () => ItemModel.shapeOf(const ItemType('shears', color: 0xC0C0C0, tool: 'shears')),
      throwsArgumentError,
      reason: 'a tool the kit cannot draw declares its shape',
    );
    expect(
      () => ItemModel.of(const ItemType('rock', color: 0x808080, shape: ItemShape.block), _blocks, _items),
      throwsArgumentError,
    );
  });

  test('a block\'s item is its block as the world draws it', () {
    expect(_model('stone').voxels, hasLength(8 * 8 * 8));
    expect(_model('stone').grip, ItemGrip.block);
    expect(_model('slab').voxels, hasLength(8 * 4 * 8));
    expect(_model('torch').grip, ItemGrip.upright);
    expect(_model('door').grip, ItemGrip.flat);
    // Every form the mesher has is drawn, and drawn standing on its origin.
    for (final form in BlockShape.values) {
      final m = ItemModel.of(
        ItemType('x', color: 0x808080, block: 'b_${form.name}'),
        BlockRegistry([
          const BlockType('air', color: 0, solid: false, hardness: -1, drop: ''),
          BlockType('b_${form.name}', color: 0x808080, shape: form, hardness: 1),
        ]),
        _items,
      );
      expect(m.voxels, isNotEmpty, reason: form.name);
      expect(m.bounds().min.y, closeTo(0.0, 1e-6), reason: form.name);
    }
  });

  test('one look is one model, whichever item has it', () {
    final pick = _model('pick');
    expect(ItemModel.of(const ItemType('other_pick', color: 0xB08850, tool: 'pickaxe'), _blocks, _items), same(pick));
    expect(
      ItemModel.of(const ItemType('iron_pick', color: 0xD0D0D0, tool: 'pickaxe'), _blocks, _items),
      isNot(same(pick)),
    );
    expect(
      ItemModel.of(const ItemType('club', color: 0xB08850, shape: ItemShape.sword), _blocks, _items),
      isNot(same(pick)),
    );
    // A block's item looks like its block, not like its own colour.
    expect(
      ItemModel.of(const ItemType('pebble', color: 0x123456, block: 'stone'), _blocks, _items),
      same(_model('stone')),
    );
  });

  test('a full pail is the empty one with its liquid in it', () {
    final empty = _model('bucket'), full = _model('water_bucket');
    expect(full, isNot(same(empty)));
    final water = _blocks[_blocks.indexOf('water')];
    final inside = full.voxels.entries.where((e) => !empty.voxels.containsKey(e.key)).toList();
    expect(inside, isNotEmpty);
    for (final e in inside) {
      expect(e.value.z / e.value.x, closeTo(water.b / water.r, 0.05), reason: 'the liquid\'s colour');
    }
    final wall = empty.voxels.keys.firstWhere((k) => k.x == -3 && k.y == 3);
    expect(full.voxels[wall]!.x, closeTo(empty.voxels[wall]!.x, 1e-9), reason: 'the empty pail\'s colour');
  });

  test('a custom shape is drawn as declared, held where it says', () {
    const staff = CustomItemShape([
      (IVec3(0, 0, 0), IVec3(0, 2, 0), 0x6B4F2A),
      (IVec3(0, 2, 0), IVec3(0, 2, 0), 0x40A0FF),
    ], grip: ItemGrip.flat);
    final m = ItemModel.of(const ItemType('staff', color: 0x40A0FF, shape: staff), _blocks, _items);
    expect(ItemModel.of(const ItemType('staff2', color: 0, shape: staff), _blocks, _items), same(m));
    expect(m.voxels, hasLength(3));
    expect(m.voxels[const IVec3(0, 2, 0)]!.z, closeTo(1.0, 0.06), reason: 'the later box paints over');
    final b = m.bounds();
    expect(b.min.x, closeTo(-ItemShape.voxelSize / 2, 1e-6));
    expect(b.max.y, closeTo(3 * ItemShape.voxelSize, 1e-6));
    expect(
      () => ItemModel.of(
        const ItemType('none', color: 0, shape: CustomItemShape([], grip: ItemGrip.flat)),
        _blocks,
        _items,
      ),
      throwsArgumentError,
    );
  });
}
