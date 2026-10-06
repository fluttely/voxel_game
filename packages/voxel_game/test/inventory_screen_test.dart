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
  items: [
    ItemType('wooden_pickaxe', color: 0xB08850, tool: 'pickaxe', tier: 1, stack: 1, durability: 60, damage: 2),
    ItemType('apple', color: 0xD03A2A, food: Food(hunger: 4)),
  ],
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
      .byWidgetPredicate((w) => w is GestureDetector && w.onSecondaryTap != null && w.child is Container)
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

  testWidgets('a long press takes half and leaves one, as a right-click does', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory..setSlot(0, ItemStack('dirt', 5));
    await tester.pump();
    await tester.longPress(slot(inv, 0));
    await tester.pump();
    expect(inv.countAt(0), 2);
    await tester.longPress(slot(inv, 1));
    await tester.pump();
    expect(inv.countAt(1), 1);
    game.dispose();
  });

  testWidgets('the held stack follows the mouse, and sits above a finger', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory..setSlot(0, ItemStack('dirt', 5));
    await tester.pump();
    final held = find.descendant(of: find.byType(IgnorePointer).last, matching: find.byType(ItemIcon));
    expect(held, findsNothing);
    final at = tester.getCenter(slot(inv, 0));
    await tester.tapAt(at);
    await tester.pump();
    expect(tester.getCenter(held), at - const Offset(0, InventoryScreen.fingerLift), reason: 'a finger would hide it');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(const Offset(30, 40));
    await tester.pump();
    expect(tester.getCenter(held), const Offset(30, 40));
    await mouse.moveTo(const Offset(70, 90));
    await tester.pump();
    expect(tester.getCenter(held), const Offset(70, 90));
    await mouse.removePointer();
    game.dispose();
  });

  testWidgets('a tooltip says what the slot under the mouse holds, read off its row', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory
      ..setSlot(0, ItemStack('wooden_pickaxe', 1, dur: 7))
      ..setSlot(1, ItemStack('apple', 3));
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(slot(inv, 0)));
    await tester.pump();
    expect(find.text('Wooden Pickaxe'), findsOneWidget);
    expect(find.text('Pickaxe, tier 1'), findsOneWidget);
    expect(find.text('Damage 2'), findsOneWidget);
    expect(find.text('Uses 7 / 60'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(slot(inv, 1)));
    await tester.pump();
    expect(find.text('Wooden Pickaxe'), findsNothing);
    expect(find.text('Food +4'), findsOneWidget);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(find.text('Apple'), findsNothing, reason: 'off the slots, with nothing held, nothing to say');
    await mouse.removePointer();
    game.dispose();
  });

  testWidgets('a finger has no hover: the tooltip says what it holds', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory..setSlot(0, ItemStack('apple', 3));
    await tester.pump();
    await tester.tap(slot(inv, 0));
    await tester.pump();
    expect(find.text('Apple'), findsOneWidget);
    await tester.tap(slot(inv, 0));
    await tester.pump();
    expect(find.text('Apple'), findsNothing);
    game.dispose();
  });

  testWidgets('a stack let go outside the panel is thrown into the world; on the panel it is not', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory..setSlot(0, ItemStack('wooden_pickaxe', 1, dur: 7));
    inv.setSlot(1, ItemStack('dirt', 5));
    await tester.pump();
    Iterable<ItemPickup> drops() => game.entities.whereType<ItemPickup>();
    await tester.tap(slot(inv, 1));
    await tester.pump();
    await tester.tap(find.text('Inventory'));
    await tester.pump();
    expect(drops(), isEmpty, reason: 'the panel is not outside it');
    await tester.tapAt(const Offset(4, 4), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(drops().single.count, 1, reason: 'a right-click throws one');
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(drops().map((d) => d.count), [1, 4]);
    expect(inv.countOf('dirt'), 0);
    await tester.tap(slot(inv, 0));
    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(drops().last.stack.dur, 7, reason: 'the stack thrown is the one held');
    game.dispose();
  });

  testWidgets('a held stack the bag has no room for when the screen shuts goes on the ground', (tester) async {
    final game = await start(tester);
    final inv = game.player.inventory;
    for (var i = 0; i < inv.capacity; i++) {
      inv.setSlot(i, ItemStack('stone', 64));
    }
    inv.setSlot(0, ItemStack('wooden_pickaxe', 1, dur: 7));
    await tester.pump();
    await tester.tap(slot(inv, 0));
    await tester.pump();
    inv.setSlot(0, ItemStack('stone', 64));
    await tester.pumpWidget(const SizedBox());
    final drop = game.entities.whereType<ItemPickup>().single;
    expect(drop.stack.dur, 7);
    game.dispose();
  });

  testWidgets('the panel shrinks to fit a phone held sideways', (tester) async {
    tester.view
      ..physicalSize = const Size(915, 412)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final game = await start(tester);
    final panel = tester.getRect(find.ancestor(of: find.text('Inventory'), matching: find.byType(Material)).first);
    expect(panel.top, greaterThanOrEqualTo(0));
    expect(panel.bottom, lessThanOrEqualTo(412));
    expect(panel.width, lessThanOrEqualTo(915));
    await tester.tap(slot(game.player.inventory, 0));
    expect(tester.takeException(), isNull);
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
