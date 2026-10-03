import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

const _spec = VoxelGameSpec(
  blocks: [
    BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
    BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType.liquid('water', color: 0x3366CC),
  ],
  items: [
    ItemType('pick', color: 0xB08850, tool: 'pickaxe', stack: 1),
    ItemType('other_pick', color: 0xB08850, tool: 'pickaxe', stack: 1),
  ],
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  player: PlayerSpec(startingItems: {'stone': 5, 'pick': 1}),
);

void main() {
  test('an item is one model in a game, shared with every item of its look', () async {
    final game = await VoxelGame.startHeadless(_spec);
    final pick = game.itemModel('pick');
    expect(game.itemModel('pick'), same(pick));
    expect(game.itemModel('other_pick'), same(pick), reason: 'the same look');
    expect(pick.grip, ItemGrip.flat);
    expect(game.itemModel('stone').grip, ItemGrip.block);
  });

  test('a spec whose item the kit cannot draw does not build', () {
    VoxelGameSpec with_(ItemType item) => _spec.copyWith(items: [item]);
    final trowel = with_(const ItemType('trowel', color: 0xC0C0C0, tool: 'trowel'));
    expect(() => trowel.buildItems(trowel.buildBlocks()), throwsArgumentError);
    final declared = with_(const ItemType('trowel', color: 0xC0C0C0, tool: 'trowel', shape: ItemShape.sword));
    expect(declared.buildItems(declared.buildBlocks()).has('trowel'), isTrue);
    final rock = with_(const ItemType('rock', color: 0x808080, shape: ItemShape.block));
    expect(() => rock.buildItems(rock.buildBlocks()), throwsArgumentError, reason: 'it places no block');
  });

  test("an icon's faces fill the slot's square, back to front, the eye seeing only outer faces", () async {
    final game = await VoxelGame.startHeadless(_spec);
    for (final id in ['stone', 'pick']) {
      final faces = ItemIcon.faces(game.itemModel(id));
      expect(faces, isNotEmpty);
      for (var i = 1; i < faces.length; i++) {
        expect(faces[i].depth, greaterThanOrEqualTo(faces[i - 1].depth), reason: '$id: painted back to front');
      }
      var lo = double.infinity, hi = double.negativeInfinity;
      for (final f in faces) {
        for (final c in f.corners) {
          expect(c.dx, inInclusiveRange(-1e-9, 1 + 1e-9));
          expect(c.dy, inInclusiveRange(-1e-9, 1 + 1e-9));
          lo = [lo, c.dx, c.dy].reduce((a, b) => a < b ? a : b);
          hi = [hi, c.dx, c.dy].reduce((a, b) => a > b ? a : b);
        }
      }
      expect(hi - lo, closeTo(ItemIcon.fill, 0.01), reason: '$id: its longer side fills the square');
    }
    // A cube from a top corner shows three faces of its outer layer: its top,
    // and two sides, 8 x 8 voxels each.
    expect(ItemIcon.faces(game.itemModel('stone')), hasLength(3 * 64));
    expect(ItemIcon.picture(game.itemModel('pick')), same(ItemIcon.picture(game.itemModel('other_pick'))));
  });

  testWidgets('the hotbar draws each slot with its item\'s icon', (tester) async {
    final game = (await tester.runAsync(() async {
      final game = await VoxelGame.startHeadless(_spec);
      game.spawner.enabled = false;
      for (var i = 0; i < 600 && !game.ready; i++) {
        game.frame(1 / 60);
        await Future<void>.delayed(Duration.zero);
      }
      return game;
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        home: GameSurface(
          game: game,
          world: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    final icons = tester.widgetList<ItemIcon>(find.byType(ItemIcon)).toList();
    expect([for (final i in icons) i.model], [game.itemModel('stone'), game.itemModel('pick')]);
  });
}
