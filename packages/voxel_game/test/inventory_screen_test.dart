import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

const _spec = VoxelGameSpec(
  blocks: [
    BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
    BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType.liquid('water', color: 0x3366CC),
    BlockType.liquid('water_flow', color: 0x3366CC, kind: 'water', source: false),
  ],
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  recipes: [
    Recipe('stone', 1, {'dirt': 2}),
    Recipe('grass', 1, {'stone': 9}),
  ],
);

/// The kit's bag over a game that never runs: the screen reads and writes only
/// the player's inventory and the recipe book.
void main() {
  Future<VoxelGame> start(WidgetTester tester) async {
    final game = (await tester.runAsync(() => VoxelGame.startHeadless(_spec)))!;
    game.spawner.enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryScreen(game: game, station: '', onClose: () {}),
      ),
    );
    return game;
  }

  // Slot [i] of [inv]: the screen lays out the bag's rows first, the hotbar
  // last.
  Finder slot(Inventory inv, int i) => find
      .byWidgetPredicate((w) => w is GestureDetector && w.onSecondaryTap != null)
      .at(i >= inv.hotbarSize ? i - inv.hotbarSize : inv.capacity - inv.hotbarSize + i);

  testWidgets('a tap takes a stack onto the cursor, and another puts it down', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory..setSlot(0, ItemStack('dirt', 5));
    await tester.pump();
    await tester.tap(slot(inv, 0));
    await tester.pump();
    expect(inv.isEmptySlot(0), isTrue);
    await tester.tap(slot(inv, 12));
    await tester.pump();
    expect(inv.idAt(12), 'dirt');
    expect(inv.countAt(12), 5);
    game.dispose();
  });

  testWidgets('a right-click takes half, and leaves one', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory..setSlot(0, ItemStack('dirt', 5));
    await tester.pump();
    Future<void> rightClick(int i) async {
      await tester.tap(slot(inv, i), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pump();
    }

    await rightClick(0);
    expect(inv.countAt(0), 2, reason: 'the larger half, 3, is on the cursor');
    await rightClick(1);
    expect(inv.countAt(1), 1);
    await rightClick(0);
    expect(inv.countAt(0), 3, reason: 'one more onto the same item');
    game.dispose();
  });

  testWidgets('a stack left on the cursor goes back into the bag when the screen shuts', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory..setSlot(0, ItemStack('dirt', 5));
    await tester.pump();
    await tester.tap(slot(inv, 0));
    await tester.pump();
    expect(inv.countOf('dirt'), 0);
    await tester.pumpWidget(const SizedBox());
    expect(inv.countOf('dirt'), 5);
    game.dispose();
  });

  testWidgets('a recipe the bag can pay for is crafted by a tap; one it cannot is off', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory..setSlot(0, ItemStack('dirt', 4));
    await tester.pump();
    ListTile tile(String text) =>
        tester.widget<ListTile>(find.ancestor(of: find.text(text), matching: find.byType(ListTile)));
    expect(tile('Grass x1').enabled, isFalse);
    expect(tile('Stone x1').enabled, isTrue);
    await tester.tap(find.text('Stone x1'));
    await tester.pump();
    expect(inv.countOf('dirt'), 2);
    expect(inv.countOf('stone'), 1);
    expect(find.text('Dirt 2/2'), findsOneWidget, reason: 'the list shows what is left');
    game.dispose();
  });
}
