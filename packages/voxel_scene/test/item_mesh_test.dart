import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test('one item model is one mesh, whoever draws it', () {
    final blocks = BlockRegistry(const [
      BlockType('air', color: 0, solid: false, hardness: -1, drop: ''),
      BlockType('stone', color: 0x808080, hardness: 3),
    ]);
    final items = ItemRegistry([
      ...ItemRegistry.forBlocks(blocks),
      const ItemType('pick', color: 0xB08850, tool: 'pickaxe'),
    ]);
    final pick = ItemModel.of(items['pick'], blocks, items);
    final mesh = ItemMesh.of(pick);
    expect(ItemMesh.of(pick), same(mesh));
    expect(mesh.model, same(pick));
    expect(ItemMesh.of(ItemModel.of(items['stone'], blocks, items)), isNot(same(mesh)));
  });
}
