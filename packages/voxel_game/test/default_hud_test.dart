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
);

/// The kit's HUD over a running game, on the `GameSurface` `VoxelGameWidget`
/// shows: one `Listener` around the world and the HUD, feeding the input map
/// every pointer that lands anywhere in it.
void main() {
  Future<VoxelGame> start(WidgetTester tester, [VoxelGameSpec spec = _spec]) async {
    final game = (await tester.runAsync(() async {
      final game = await VoxelGame.startHeadless(spec);
      game.spawner.enabled = false;
      for (var i = 0; i < 600 && !game.ready; i++) {
        game.frame(1 / 60);
        await Future<void>.delayed(Duration.zero);
      }
      return game;
    }))!;
    expect(game.ready, isTrue);
    game.input.wantCapture = true;
    await tester.pumpWidget(
      MaterialApp(
        home: GameSurface(
          game: game,
          world: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    return game;
  }

  // One step of the game, then the HUD's rebuild.
  Future<void> step(WidgetTester tester, VoxelGame game) async {
    game.frame(1 / 30);
    await tester.pump();
  }

  Finder slot(int i) => find.descendant(of: find.byType(DefaultHud), matching: find.byType(RawGestureDetector)).at(i);

  testWidgets('a tap on a slot picks it, and is not also a tap on the world', (tester) async {
    final game = await start(tester);
    final input = game.input;
    await tester.tap(slot(3));
    expect(input.digitPressed(), 3);
    expect(input.justPressed(VoxelAction.use), isFalse);
    expect(input.justPressed(VoxelAction.attack), isFalse);
    await step(tester, game);
    expect(game.player.selectedSlot, 3);
    // The same finger off the hotbar is the world's.
    await tester.tapAt(const Offset(100, 100));
    expect(input.justPressed(VoxelAction.use), isTrue);
    game.dispose();
  });

  testWidgets('a hold on the slot in hand drops one', (tester) async {
    final game = await start(tester);
    final p = game.player;
    p.inventory.add('dirt', 5);
    await step(tester, game);
    expect(p.selectedSlot, 0);
    expect(p.inventory.countAt(0), 5);
    await tester.longPress(slot(0));
    expect(game.input.justPressed(VoxelAction.drop), isTrue);
    expect(game.input.justPressed(VoxelAction.use), isFalse);
    await step(tester, game);
    expect(p.inventory.countAt(0), 4);
    // A hold on a slot not in hand picks it, and drops nothing.
    await tester.longPress(slot(2));
    expect(game.input.justPressed(VoxelAction.drop), isFalse);
    expect(game.input.digitPressed(), 2);
    game.dispose();
  });

  testWidgets('a mouse over the hotbar is the world\'s', (tester) async {
    final game = await start(tester);
    final input = game.input;
    await tester.tap(slot(3), kind: PointerDeviceKind.mouse);
    expect(input.digitPressed(), -1);
    expect(input.justPressed(VoxelAction.attack), isTrue, reason: 'the click swings at the world');
    await step(tester, game);
    expect(game.player.selectedSlot, 0);
    game.dispose();
  });

  testWidgets('the bag button is a finger\'s, and opens the bag', (tester) async {
    final game = await start(tester);
    final input = game.input..lastDevice = InputDevice.keyboardMouse;
    await step(tester, game);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    input.lastDevice = InputDevice.touch;
    await step(tester, game);
    await tester.tap(find.byIcon(Icons.more_horiz));
    expect(input.justPressed(VoxelAction.inventory), isTrue);
    expect(input.justPressed(VoxelAction.use), isFalse);
    await step(tester, game);
    expect(game.screen.value, const BagScreen());
    game.dispose();
  });

  testWidgets('a game with no touch controls gets a hotbar that takes no finger', (tester) async {
    final game = await start(tester, _spec.copyWith(touchControls: () => null));
    game.input.lastDevice = InputDevice.touch;
    await step(tester, game);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.descendant(of: find.byType(DefaultHud), matching: find.byType(RawGestureDetector)), findsNothing);
    game.dispose();
  });

  testWidgets('the hint speaks to the device in hand', (tester) async {
    final game = await start(tester);
    final input = game.input..wantCapture = false;
    input.lastDevice = InputDevice.touch;
    await step(tester, game);
    expect(find.text('Tap to play'), findsOneWidget);
    input.lastDevice = InputDevice.keyboardMouse;
    await step(tester, game);
    expect(find.textContaining('Click to play'), findsOneWidget);
    game.dispose();
  });

  // The icons of [icon] drawn in [color] in the HUD.
  int icons(IconData icon, {Color? color}) => find
      .descendant(of: find.byType(DefaultHud), matching: find.byIcon(icon))
      .evaluate()
      .where((e) => color == null || (e.widget as Icon).color == color)
      .length;

  testWidgets('a bar shows only what the spec declares', (tester) async {
    final game = await start(tester);
    await step(tester, game);
    expect(icons(Icons.favorite), 10);
    expect(icons(Icons.restaurant), 0, reason: 'no PlayerSpec.hunger');
    expect(icons(Icons.shield), 0, reason: 'no armour');
    expect(find.byType(LinearProgressIndicator), findsNothing, reason: 'no PlayerSpec.xp, and nothing mined');
    expect(find.textContaining('Regeneration'), findsNothing);
    game.dispose();
  });

  testWidgets('hunger sits beside the hearts, two points an icon', (tester) async {
    final game = await start(tester, _spec.copyWith(player: const PlayerSpec(hunger: HungerSpec())));
    final orange = Colors.orange.shade300;
    await step(tester, game);
    expect(icons(Icons.restaurant, color: orange), 10);
    game.player.hunger = 9;
    await step(tester, game);
    expect(icons(Icons.restaurant, color: orange), 4);
    expect(icons(Icons.restaurant, color: orange.withValues(alpha: 0.5)), 1);
    expect(icons(Icons.restaurant, color: Colors.white24), 5);
    game.dispose();
  });

  testWidgets('armour shows over the hearts while there is any', (tester) async {
    final game = await start(
      tester,
      _spec.copyWith(
        effects: const [
          EffectType('iron_skin', 'Iron skin', 0.6, 0.6, 0.7, stats: {PlayerEntity.armorStat: StatModifier.add(3)}),
        ],
      ),
    );
    await step(tester, game);
    expect(icons(Icons.shield) + icons(Icons.shield_outlined), 0);
    game.player.effects.apply('iron_skin', 30);
    await step(tester, game);
    expect(icons(Icons.shield), 1);
    expect(icons(Icons.shield_outlined), 1);
    game.dispose();
  });

  testWidgets('experience is a bar under the hearts, with the level on it', (tester) async {
    final game = await start(tester, _spec.copyWith(player: const PlayerSpec(xp: XpSpec(base: 10, exponent: 0))));
    await step(tester, game);
    LinearProgressIndicator bar() => tester.widget(find.byType(LinearProgressIndicator));
    expect(bar().value, 0.0);
    expect(find.text('0'), findsNothing, reason: 'level 0 shows no number');
    game.player.gainXp(25);
    await step(tester, game);
    expect(find.text('2'), findsOneWidget);
    expect(bar().value, 0.5);
    game.dispose();
  });

  testWidgets('each effect shows its name, its power past the first and its time left', (tester) async {
    final game = await start(
      tester,
      _spec.copyWith(
        effects: const [
          EffectType('regeneration', 'Regeneration', 0.9, 0.35, 0.55, period: 2.0, heal: 1.0),
          EffectType('poison', 'Poison', 0.3, 0.6, 0.2, period: 1.0, damage: 0.5, bad: true),
        ],
      ),
    );
    final effects = game.player.effects;
    effects.apply('regeneration', 75, 2);
    effects.apply('poison', 3);
    await step(tester, game);
    expect(find.text('Regeneration 2  1:15'), findsOneWidget);
    expect(find.text('Poison  3s'), findsOneWidget);
    // A bit over four seconds, a step a frame.
    for (var i = 0; i < 250; i++) {
      game.frame(1 / 60);
    }
    await tester.pump();
    expect(find.text('Regeneration 2  1:11'), findsOneWidget);
    expect(find.textContaining('Poison'), findsNothing, reason: 'it ran out');
    game.dispose();
  });

  testWidgets('the game\'s notices and the pickups show at the right, then go', (tester) async {
    final game = await start(tester);
    game.notify('A chest is full');
    game.player.pickUp('dirt', 3);
    await step(tester, game);
    expect(find.text('A chest is full'), findsOneWidget);
    expect(find.text('+3 Dirt'), findsOneWidget);
    game.player.pickUp('dirt', 2);
    await step(tester, game);
    expect(find.text('+5 Dirt'), findsOneWidget, reason: 'a pickup soon after the last adds to its line');
    for (var i = 0; i < 4 * 60; i++) {
      game.frame(1 / 60);
    }
    await tester.pumpAndSettle();
    expect(find.text('A chest is full'), findsNothing);
    expect(find.text('+5 Dirt'), findsNothing);
    game.dispose();
  });
}
