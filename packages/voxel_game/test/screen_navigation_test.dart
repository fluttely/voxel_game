import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:voxel_game/voxel_game.dart';

final List<String> _pressed = [];

Widget _journal(BuildContext context, VoxelGame game) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FilledButton(onPressed: () => _pressed.add('north'), child: const Text('North')),
      FilledButton(onPressed: () => _pressed.add('south'), child: const Text('South')),
    ],
  ),
);

/// Level grass, a quick respawn, a recipe, and a screen of the game's own
/// built of plain Material buttons, with no focus code of its own.
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
  sky: SkySpec.alwaysDay,
  player: PlayerSpec(respawnDelay: 0.5),
  recipes: [
    Recipe('stone', 1, {'dirt': 2}),
  ],
  screens: {'journal': ScreenSpec(_journal, menu: 'Journal')},
);

NormalizedGamepadEvent _button(GamepadButton button, double value) => NormalizedGamepadEvent(
  gamepadId: 'pad',
  timestamp: 0,
  button: button,
  value: value,
  rawEvent: GamepadEvent(gamepadId: 'pad', timestamp: 0, type: KeyType.button, key: 'k', value: value),
);

NormalizedGamepadEvent _axis(GamepadAxis axis, double value) => NormalizedGamepadEvent(
  gamepadId: 'pad',
  timestamp: 0,
  axis: axis,
  value: value,
  rawEvent: GamepadEvent(gamepadId: 'pad', timestamp: 0, type: KeyType.analog, key: 'k', value: value),
);

/// The kit's screens — the game menu, the settings, the death screen, the
/// bag, a game's own — worked by a pad alone and by the keys alone, over the
/// surface `VoxelGameWidget` shows ([GameSurface] over a plain box); and the
/// title, which has no game under it, worked the same ways.
void main() {
  setUp(_pressed.clear);

  Future<VoxelGame> start(WidgetTester tester) async {
    final game = (await tester.runAsync(() async {
      final game = await VoxelGame.startHeadless(_spec);
      game.spawner.enabled = false;
      for (var i = 0; i < 600 && !game.ready; i++) {
        game.frame(1 / 60);
        await Future<void>.delayed(Duration.zero);
      }
      return game;
    }))!;
    expect(game.ready, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: GameSurface(
          game: game,
          world: const ColoredBox(color: Colors.black),
          onQuit: () {},
        ),
      ),
    );
    return game;
  }

  // A build, then the post-frame and the autofocus it leaves.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> pad(WidgetTester tester, VoxelGame game, GamepadButton button) async {
    game.input.onPad(_button(button, 1));
    await tester.pump();
    game.input.onPad(_button(button, 0));
    await settle(tester);
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  // The step's arbiter, which reads what backing out pressed.
  Future<void> step(WidgetTester tester, VoxelGame game) async {
    game.frame(1 / 60);
    await settle(tester);
  }

  bool focused(WidgetTester tester, Finder target) {
    final element = tester.element(target);
    final focus = FocusManager.instance.primaryFocus!.context!;
    if (identical(focus, element)) return true;
    var inside = false;
    focus.visitAncestorElements((e) {
      inside = identical(e, element);
      return !inside;
    });
    return inside;
  }

  Finder button(String label) =>
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
  Finder tile(String label) => find.widgetWithText(SwitchListTile, label);
  Finder slider(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
    matching: find.byType(Slider),
  );

  testWidgets('a pad alone works the game menu and the settings', (tester) async {
    final game = await start(tester);
    game.openScreen(const PauseScreen());
    await settle(tester);
    expect(focused(tester, button('Resume')), isTrue, reason: 'the menu opens on Resume');
    final ring = Theme.of(tester.element(find.text('Resume'))).filledButtonTheme.style!.side!;
    expect(ring.resolve({WidgetState.focused}), ScreenFocus.ring, reason: 'and draws the focus');

    await pad(tester, game, GamepadButton.dpadDown);
    expect(focused(tester, button('Settings')), isTrue);
    await pad(tester, game, GamepadButton.dpadUp);
    expect(focused(tester, button('Resume')), isTrue);
    await pad(tester, game, GamepadButton.dpadDown);
    await pad(tester, game, GamepadButton.a);
    expect(game.screen.value, const SettingsScreen());
    expect(game.input.padPressed(GamepadButton.a), isFalse, reason: 'the press was the screen\'s, not a jump');

    expect(focused(tester, slider('Render distance')), isTrue, reason: 'the settings open on the first row');
    final distance = game.settings.value.renderDistance;
    await pad(tester, game, GamepadButton.dpadRight);
    expect(game.settings.value.renderDistance, distance + 1, reason: 'right moves the slider a step');
    await pad(tester, game, GamepadButton.dpadLeft);
    expect(game.settings.value.renderDistance, distance);

    final bob = game.settings.value.viewBob;
    for (var i = 0; i < 10 && !focused(tester, tile('View bobbing')); i++) {
      await pad(tester, game, GamepadButton.dpadDown);
    }
    expect(focused(tester, tile('View bobbing')), isTrue, reason: 'down goes from row to row');
    await pad(tester, game, GamepadButton.a);
    expect(game.settings.value.viewBob, !bob, reason: 'A flips the switch');

    await pad(tester, game, GamepadButton.b);
    await step(tester, game);
    expect(game.screen.value, const PauseScreen(), reason: 'B backs out to the game menu');
    expect(focused(tester, button('Resume')), isTrue);
    await pad(tester, game, GamepadButton.b);
    await step(tester, game);
    expect(game.screen.value, isNull, reason: 'and out of it');
    game.dispose();
  });

  testWidgets('the keys alone work the game menu and the settings', (tester) async {
    final game = await start(tester);
    game.openScreen(const PauseScreen());
    await settle(tester);
    expect(focused(tester, button('Resume')), isTrue);

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, button('Settings')), isTrue);
    await key(tester, LogicalKeyboardKey.enter);
    expect(game.screen.value, const SettingsScreen());
    expect(game.input.keyPressed(PhysicalKeyboardKey.enter), isFalse, reason: 'the key was the screen\'s');

    expect(focused(tester, slider('Render distance')), isTrue);
    final distance = game.settings.value.renderDistance;
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(game.settings.value.renderDistance, distance + 1);

    final fps = game.settings.value.showFps;
    for (var i = 0; i < 10 && !focused(tester, tile('Show FPS')); i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focused(tester, tile('Show FPS')), isTrue, reason: 'up and down leave a slider');
    await key(tester, LogicalKeyboardKey.space);
    expect(game.settings.value.showFps, !fps);

    await key(tester, LogicalKeyboardKey.escape);
    await step(tester, game);
    expect(game.screen.value, const PauseScreen());
    await key(tester, LogicalKeyboardKey.escape);
    await step(tester, game);
    expect(game.screen.value, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    expect(game.input.down(VoxelAction.moveForward), isTrue, reason: 'the keys are the game\'s again');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    game.dispose();
  });

  testWidgets('a held direction repeats, and the left stick points like the dpad', (tester) async {
    final game = await start(tester);
    game.openScreen(const PauseScreen());
    await settle(tester);

    game.input.onPad(_axis(GamepadAxis.leftStickY, -0.9));
    await settle(tester);
    expect(focused(tester, button('Settings')), isTrue, reason: 'a flick moves once at once');
    await tester.pump(FocusBridge.repeatDelay);
    await settle(tester);
    expect(focused(tester, button('Journal')), isTrue, reason: 'held, it repeats');
    await tester.pump(FocusBridge.repeatEvery);
    await settle(tester);
    expect(focused(tester, button('Quit')), isTrue);
    game.input.onPad(_axis(GamepadAxis.leftStickY, 0.1));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(focused(tester, button('Quit')), isTrue, reason: 'let go, it stops');

    game.input.onPad(_button(GamepadButton.dpadUp, 1));
    await settle(tester);
    expect(focused(tester, button('Journal')), isTrue);
    await tester.pump(FocusBridge.repeatDelay);
    await settle(tester);
    expect(focused(tester, button('Settings')), isTrue);
    game.input.onPad(_button(GamepadButton.dpadUp, 0));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(focused(tester, button('Settings')), isTrue);
    game.dispose();
  });

  testWidgets('the death screen holds the focus on Respawn asleep; A stands up once it wakes', (tester) async {
    final game = await start(tester);
    game.player.takeDamage(const Damage(1000, source: 'test'));
    await settle(tester);
    expect(game.screen.value, const DeathScreen());
    expect(focused(tester, button('Respawn')), isTrue);
    await pad(tester, game, GamepadButton.a);
    expect(game.screen.value, const DeathScreen(), reason: 'not before the delay');
    for (var i = 0; i < 40; i++) {
      game.frame(1 / 60);
    }
    await settle(tester);
    expect(game.canRespawn, isTrue);
    expect(focused(tester, button('Respawn')), isTrue, reason: 'the focus stayed while it slept');
    await pad(tester, game, GamepadButton.a);
    expect(game.screen.value, isNull);
    expect(game.player.isDead, isFalse);
    game.dispose();
  });

  testWidgets('the death screen by the keys: Enter stands up once it wakes', (tester) async {
    final game = await start(tester);
    game.player.takeDamage(const Damage(1000, source: 'test'));
    await settle(tester);
    expect(focused(tester, button('Respawn')), isTrue);
    for (var i = 0; i < 40; i++) {
      game.frame(1 / 60);
    }
    await settle(tester);
    await key(tester, LogicalKeyboardKey.enter);
    expect(game.screen.value, isNull);
    game.dispose();
  });

  testWidgets('a game\'s screen of Material buttons is worked by a pad and the keys with no focus code', (
    tester,
  ) async {
    final game = await start(tester);
    game.openScreen(const DeclaredScreen('journal'));
    await settle(tester);
    await pad(tester, game, GamepadButton.dpadDown);
    expect(focused(tester, button('North')), isTrue, reason: 'the first direction lands on the screen');
    await pad(tester, game, GamepadButton.dpadDown);
    await pad(tester, game, GamepadButton.a);
    expect(_pressed, ['south']);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.enter);
    expect(_pressed, ['south', 'north']);
    await pad(tester, game, GamepadButton.b);
    await step(tester, game);
    expect(game.screen.value, isNull, reason: 'B backs out of it as pause does');
    game.dispose();
  });

  testWidgets('a focused tab is filled; the game\'s own overlay keeps the other states', (tester) async {
    const hover = Color(0xFF123456);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(tabBarTheme: TabBarThemeData(overlayColor: WidgetStatePropertyAll(hover))),
        home: const Scaffold(
          body: ScreenFocus(
            child: DefaultTabController(
              length: 2,
              child: TabBar(
                tabs: [
                  Tab(text: 'One'),
                  Tab(text: 'Two'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final overlay = TabBarTheme.of(tester.element(find.text('One'))).overlayColor!;
    expect(overlay.resolve({WidgetState.focused}), ScreenFocus.fill);
    expect(overlay.resolve({WidgetState.hovered}), hover);
  });

  testWidgets('with no screen open, the pad and the arrows are the game\'s', (tester) async {
    final game = await start(tester);
    game.input.onPad(_button(GamepadButton.a, 1));
    expect(game.input.justPressed(VoxelAction.jump), isTrue);
    game.input.onPad(_button(GamepadButton.a, 0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    expect(game.input.keyDown(PhysicalKeyboardKey.arrowUp), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    game.dispose();
  });

  // Slot [i] of [inv] as the bag lays it out (the bag's rows first, the
  // hotbar last), and the widget that takes its focus.
  Finder slot(Inventory inv, int i) => find
      .byWidgetPredicate((w) => w is GestureDetector && w.onSecondaryTap != null && w.child is Container)
      .at(i >= inv.hotbarSize ? i - inv.hotbarSize : inv.capacity - inv.hotbarSize + i);
  Finder slotFocus(Inventory inv, int i) =>
      find.ancestor(of: slot(inv, i), matching: find.byType(FocusableActionDetector)).first;
  Finder recipe(String label) => find.ancestor(of: find.text(label), matching: find.byType(ListTile));

  /// Picks the stack in hand up, puts it down a slot over, takes half of it
  /// back, puts that down a slot further, and crafts, with [move], [press]
  /// (A) and [half] (X) alone; [back] (B) closes the bag.
  Future<void> workTheBag(
    WidgetTester tester,
    VoxelGame game, {
    required Future<void> Function(TraversalDirection) move,
    required Future<void> Function() press,
    required Future<void> Function() half,
    required Future<void> Function() back,
  }) async {
    final inv = game.player.inventory..setSlot(0, ItemStack('dirt', 5));
    game.openScreen(const BagScreen());
    await settle(tester);
    expect(focused(tester, slotFocus(inv, 0)), isTrue, reason: 'the bag opens on the slot in hand');

    await press();
    expect(inv.isEmptySlot(0), isTrue, reason: 'A picks the stack up');
    expect(game.player.carried!.count, 5);
    await move(TraversalDirection.right);
    expect(focused(tester, slotFocus(inv, 1)), isTrue);
    final held = find.descendant(of: find.byType(IgnorePointer).last, matching: find.byType(ItemIcon));
    expect(tester.getCenter(held), tester.getTopRight(slotFocus(inv, 1)), reason: 'the held stack is by the focus');
    await press();
    expect(inv.countAt(1), 5, reason: 'and puts it down');
    expect(game.player.carried, isNull);

    await half();
    expect(inv.countAt(1), 2, reason: 'X takes half, the larger on the cursor');
    expect(game.player.carried!.count, 3);
    await move(TraversalDirection.right);
    await press();
    expect(inv.countAt(2), 3);

    for (var i = 0; i < 12 && !focused(tester, recipe('Stone x1')); i++) {
      await move(TraversalDirection.right);
    }
    expect(focused(tester, recipe('Stone x1')), isTrue, reason: 'right from the hotbar reaches the recipes');
    await press();
    expect(inv.countOf('stone'), 1, reason: 'A crafts');
    expect(inv.countOf('dirt'), 3);
    await press();
    expect(inv.countOf('dirt'), 1);
    expect(tester.widget<ListTile>(recipe('Stone x1')).enabled, isFalse);
    expect(focused(tester, recipe('Stone x1')), isTrue);
    final fill = find.descendant(
      of: find.ancestor(of: recipe('Stone x1'), matching: find.byType(FocusFill)),
      matching: find.byType(Material),
    );
    expect(tester.widget<Material>(fill.first).color, ScreenFocus.fill, reason: 'one it cannot make still shows it');
    await move(TraversalDirection.up);
    final close = find.byType(IconButton);
    expect(focused(tester, close), isTrue, reason: 'up from the first recipe is the close button');
    final ring = Theme.of(tester.element(close)).iconButtonTheme.style!.side!;
    expect(ring.resolve({WidgetState.focused}), ScreenFocus.ring);

    await back();
    await step(tester, game);
    expect(game.screen.value, isNull, reason: 'backing out closes the bag');
  }

  testWidgets('a pad alone picks, halves, places and crafts in the bag', (tester) async {
    final game = await start(tester);
    await workTheBag(
      tester,
      game,
      move: (way) => pad(tester, game, switch (way) {
        TraversalDirection.right => GamepadButton.dpadRight,
        TraversalDirection.left => GamepadButton.dpadLeft,
        TraversalDirection.up => GamepadButton.dpadUp,
        TraversalDirection.down => GamepadButton.dpadDown,
      }),
      press: () => pad(tester, game, GamepadButton.a),
      half: () => pad(tester, game, GamepadButton.x),
      back: () => pad(tester, game, GamepadButton.b),
    );
    expect(game.input.padPressed(GamepadButton.x), isFalse, reason: 'X on a slot was the bag\'s');
    game.dispose();
  });

  testWidgets('the keys alone pick, halve, place and craft in the bag', (tester) async {
    final game = await start(tester);
    await workTheBag(
      tester,
      game,
      move: (way) => key(tester, switch (way) {
        TraversalDirection.right => LogicalKeyboardKey.arrowRight,
        TraversalDirection.left => LogicalKeyboardKey.arrowLeft,
        TraversalDirection.up => LogicalKeyboardKey.arrowUp,
        TraversalDirection.down => LogicalKeyboardKey.arrowDown,
      }),
      press: () => key(tester, LogicalKeyboardKey.enter),
      half: () => key(tester, LogicalKeyboardKey.keyX),
      back: () => key(tester, LogicalKeyboardKey.escape),
    );
    game.dispose();
  });

  testWidgets('off a slot, X is still the game\'s', (tester) async {
    final game = await start(tester);
    game.openScreen(const PauseScreen());
    await settle(tester);
    game.input.onPad(_button(GamepadButton.x, 1));
    expect(game.input.padPressed(GamepadButton.x), isTrue, reason: 'nothing on the menu takes half');
    game.input.onPad(_button(GamepadButton.x, 0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
    expect(game.input.keyDown(PhysicalKeyboardKey.keyX), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    expect(focused(tester, button('Resume')), isTrue);
    game.dispose();
  });

  testWidgets('the credits open on Back, and the keys leave them', (tester) async {
    var back = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreditsRoll(lines: const ['Credits', 'someone'], onBack: () => back++),
        ),
      ),
    );
    await settle(tester);
    expect(focused(tester, button('Back')), isTrue);
    await key(tester, LogicalKeyboardKey.enter);
    expect(back, 1);
    await tester.pumpAndSettle();
  });

  group('the title', () {
    late StreamController<NormalizedGamepadEvent> pads;
    late WorldSaves saves;
    late List<TitleChoice> picked;

    setUp(() {
      pads = StreamController();
      final dir = Directory.systemTemp.createTempSync('voxel_title');
      addTearDown(() => dir.deleteSync(recursive: true));
      saves = WorldSaves(dir);
      picked = [];
    });
    tearDown(() => pads.close());

    Future<void> mount(
      WidgetTester tester, {
      TitleSpec menu = const TitleSpec(name: 'Blocks', credits: ['Blocks', 'by us']),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TitleScreen(
            spec: _spec,
            menu: menu,
            saves: saves,
            settings: SettingsStore(File('${saves.directory.path}/settings.json')),
            onChoice: picked.add,
            pad: pads.stream,
          ),
        ),
      );
      await settle(tester);
    }

    // The stream hands the event on in a microtask, which the pump runs.
    Future<void> press(WidgetTester tester, GamepadButton button) async {
      pads.add(_button(button, 1));
      await tester.pump();
      pads.add(_button(button, 0));
      await settle(tester);
    }

    Future<void> padTo(WidgetTester tester, GamepadButton way, Finder target) async {
      for (var i = 0; i < 10 && !focused(tester, target); i++) {
        await press(tester, way);
      }
      expect(focused(tester, target), isTrue);
    }

    Finder field(String label) => find.widgetWithText(TextField, label);

    testWidgets('a pad alone rolls the credits and makes a world to play', (tester) async {
      await mount(tester);
      expect(focused(tester, button('Play')), isTrue, reason: 'the title opens on Play');

      await padTo(tester, GamepadButton.dpadDown, button('Credits'));
      await press(tester, GamepadButton.a);
      expect(find.text('by us'), findsOneWidget);
      expect(focused(tester, button('Back')), isTrue, reason: 'the credits open on Back');
      await press(tester, GamepadButton.b);
      expect(find.text('by us'), findsNothing, reason: 'B backs out to the menu');
      expect(focused(tester, button('Play')), isTrue);

      await press(tester, GamepadButton.a);
      expect(find.text('Worlds'), findsOneWidget);
      expect(focused(tester, button('New world')), isTrue, reason: 'no world to play yet');
      await press(tester, GamepadButton.a);
      expect(focused(tester, field('Name')), isTrue, reason: 'the form opens on the name');
      await press(tester, GamepadButton.b);
      expect(field('Name'), findsNothing, reason: 'B cancels the form, and stays in the list');
      expect(find.text('Worlds'), findsOneWidget);
      expect(focused(tester, button('New world')), isTrue);

      await press(tester, GamepadButton.a);
      await padTo(tester, GamepadButton.dpadDown, button('Create'));
      await press(tester, GamepadButton.a);
      expect(picked.single, isA<PlayWorld>().having((p) => p.slot, 'slot', saves.list().single));
      expect(saves.info(saves.list().single).name, 'New world');
    });

    testWidgets('a pad works a dialog over the title, and B leaves the worlds', (tester) async {
      saves.create('Home', seed: 1);
      await mount(tester);
      await press(tester, GamepadButton.a);
      expect(focused(tester, button('Play')), isTrue, reason: 'the last played is selected');
      await padTo(tester, GamepadButton.dpadRight, button('Rename'));
      await press(tester, GamepadButton.a);
      await tester.pumpAndSettle();
      expect(find.text('Rename world'), findsOneWidget);
      await padTo(tester, GamepadButton.dpadDown, button('Cancel'));
      await press(tester, GamepadButton.b);
      await tester.pumpAndSettle();
      expect(find.text('Rename world'), findsNothing, reason: 'B closes the dialog');
      expect(focused(tester, button('Rename')), isTrue, reason: 'and the focus is back where it was');

      await press(tester, GamepadButton.b);
      expect(find.text('Worlds'), findsNothing);
      await press(tester, GamepadButton.a);
      await press(tester, GamepadButton.a);
      expect(picked.single, isA<PlayWorld>().having((p) => p.slot, 'slot', 'home'));
    });

    testWidgets('a pad picks from a dropdown\'s menu', (tester) async {
      await mount(
        tester,
        menu: const TitleSpec(
          name: 'Blocks',
          worldOptions: [
            WorldOption('class', label: 'Class', choices: {'warrior': 'Warrior', 'mage': 'Mage'}),
          ],
        ),
      );
      await press(tester, GamepadButton.a);
      await press(tester, GamepadButton.a);
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await padTo(tester, GamepadButton.dpadDown, dropdown);
      await press(tester, GamepadButton.a);
      await tester.pumpAndSettle();
      final mage = find.ancestor(of: find.text('Mage').last, matching: find.byType(InkWell)).first;
      await padTo(tester, GamepadButton.dpadDown, mage);
      await press(tester, GamepadButton.a);
      await tester.pumpAndSettle();
      expect(focused(tester, dropdown), isTrue, reason: 'the menu closed, back on its button');
      await padTo(tester, GamepadButton.dpadDown, button('Create'));
      await press(tester, GamepadButton.a);
      expect(saves.info(saves.list().single).options, {'class': 'mage'});
    });

    testWidgets('the keys alone play a world, and a text field keeps its own', (tester) async {
      saves.create('Home', seed: 1);
      await mount(tester);
      expect(focused(tester, button('Play')), isTrue);
      await key(tester, LogicalKeyboardKey.enter);
      expect(focused(tester, button('Play')), isTrue);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(tester, button('New world')), isTrue);
      await key(tester, LogicalKeyboardKey.space);
      expect(focused(tester, field('Name')), isTrue);

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isFalse, reason: 'Space goes on to be typed');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(focused(tester, field('Name')), isTrue, reason: 'the arrows are the caret\'s');
      await key(tester, LogicalKeyboardKey.escape);
      expect(field('Name'), findsNothing, reason: 'Esc cancels the form');

      await key(tester, LogicalKeyboardKey.escape);
      expect(find.text('Worlds'), findsNothing, reason: 'and the list');
      await key(tester, LogicalKeyboardKey.enter);
      await key(tester, LogicalKeyboardKey.enter);
      expect(picked.single, isA<PlayWorld>().having((p) => p.slot, 'slot', 'home'));
    });
  });
}
