import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/classes/class_system.dart';
import 'package:voxel_game_minecraft/src/journal/tutorial.dart';
import 'package:voxel_game_minecraft/src/map/world_map.dart';
import 'package:voxel_game_minecraft/src/playground/playground.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/villages/trade_screen.dart';
import 'package:voxel_game_minecraft/src/villages/villages.dart';
import 'package:voxel_game_minecraft/src/waypoints/waypoints.dart';

NormalizedGamepadEvent _button(GamepadButton button, double value) => NormalizedGamepadEvent(
  gamepadId: 'pad',
  timestamp: 0,
  button: button,
  value: value,
  rawEvent: GamepadEvent(gamepadId: 'pad', timestamp: 0, type: KeyType.button, key: 'k', value: value),
);

/// The game's own screens — the journal, the trade, the stats, the map, the
/// controls, the tutorial's and the playground's — worked by a pad alone and
/// by the keys alone, over the surface the kit shows them on: each opens with
/// a focus, and every row or button a pointer reaches, a pad reaches too.
void main() {
  Future<VoxelGame> start(WidgetTester tester, {bool tutorialDone = true}) async {
    final game = (await tester.runAsync(() async {
      final game = await VoxelGame.startHeadless(
        gameSpec,
        options: const {'class': 'warrior'},
        settings: GameSettings.of(gameSpec).copyWith(game: {Tutorial.doneKey: tutorialDone}),
      );
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

  Future<void> open(WidgetTester tester, VoxelGame game, String screen) async {
    game.openScreen(DeclaredScreen(screen));
    await settle(tester);
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

  // A step of the game: the arbiter reads what backing out pressed, and the
  // screens' selectors what changed.
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
  Finder inkOf(String text) => find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first;
  Finder tile(String title) => find.ancestor(of: find.text(title), matching: find.byType(ListTile));
  Finder section(String way) => find.ancestor(of: find.text(way), matching: find.byType(Focus)).first;
  ScrollPosition list(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(TabBarView),
          matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down),
        ),
      )
      .position;

  testWidgets('a pad alone works the journal: a tab, a talent learned, a long list walked', (tester) async {
    final game = await start(tester);
    ClassSystem.of(game).points = 1;
    await open(tester, game, 'journal');
    expect(focused(tester, inkOf('Talents')), isTrue, reason: 'the journal opens on its tab');

    var stops = 0;
    for (; stops < 40 && !focused(tester, button('Back to the game')); stops++) {
      await pad(tester, game, GamepadButton.dpadDown);
    }
    expect(stops - 1, ClassSystem.of(game).talents.length, reason: 'one stop a talent: its row, not its button');
    while (!focused(tester, find.byType(TabBar))) {
      await pad(tester, game, GamepadButton.dpadUp);
    }
    await pad(tester, game, GamepadButton.dpadDown);
    expect(focused(tester, tile('Vitality  0/3')), isTrue, reason: 'down goes to the first row');
    await pad(tester, game, GamepadButton.a);
    await step(tester, game);
    expect(find.text('Vitality  1/3'), findsOneWidget, reason: 'A on a row learns it');
    expect(ClassSystem.of(game).points, 0);
    expect(game.input.padPressed(GamepadButton.a), isFalse, reason: 'the press was the screen\'s, not a jump');

    await pad(tester, game, GamepadButton.dpadUp);
    expect(focused(tester, find.byType(TabBar)), isTrue, reason: 'up goes back to the tabs');
    for (var i = 0; i < 4 && !focused(tester, inkOf('Talents')); i++) {
      await pad(tester, game, GamepadButton.dpadLeft);
    }
    expect(focused(tester, inkOf('Talents')), isTrue);
    await pad(tester, game, GamepadButton.dpadRight);
    expect(focused(tester, inkOf('Creatures')), isTrue, reason: 'right goes from tab to tab');
    await pad(tester, game, GamepadButton.a);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('???'), findsWidgets, reason: 'A opens the tab');

    await pad(tester, game, GamepadButton.dpadDown);
    expect(list(tester).pixels, 0.0);
    for (var i = 0; i < 80 && !focused(tester, button('Back to the game')); i++) {
      await pad(tester, game, GamepadButton.dpadDown);
    }
    expect(focused(tester, button('Back to the game')), isTrue, reason: 'every creature is a stop, then Back');
    expect(list(tester).pixels, list(tester).maxScrollExtent, reason: 'the list scrolled under the focus');
    expect(list(tester).maxScrollExtent, greaterThan(0.0));

    await pad(tester, game, GamepadButton.b);
    await step(tester, game);
    expect(game.screen.value, isNull, reason: 'B backs out of it');
    game.dispose();
  });

  testWidgets('the keys alone work the journal, open on its waypoints from a waypoint', (tester) async {
    final game = await start(tester);
    await open(tester, game, Waypoints.screen);
    expect(focused(tester, inkOf('Waypoints')), isTrue, reason: 'it opens on the tab it was opened on');
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(tester, inkOf('Achievements')), isTrue);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0 / 22 unlocked'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<ListTile>(), isNotNull);
    await key(tester, LogicalKeyboardKey.escape);
    await step(tester, game);
    expect(game.screen.value, isNull);
    game.dispose();
  });

  testWidgets('the trade: a pad and the keys walk the offers, ringed, and trade', (tester) async {
    final game = await start(tester);
    final villager = game.spawnMob(Villages.villager, game.player.position + Vector3(3, 0.5, 0));
    villager.data[Villages.offersKey] = [
      ['wheat', 3, 'gold_ingot', 1],
      ['gold_ingot', 1, 'bread', 4],
    ];
    final bag = game.player.inventory;
    bag.add('wheat', 3);
    bag.add('gold_ingot', 1);
    Villages.use(game, villager);
    await settle(tester);
    Finder row(int i) => find.descendant(of: find.byType(TradeScreen), matching: find.byType(InkWell)).at(i);
    bool ringed(int i) =>
        tester
            .widget<Container>(find.descendant(of: row(i), matching: find.byType(Container)).first)
            .foregroundDecoration !=
        null;
    expect(focused(tester, row(0)), isTrue, reason: 'it opens on the first offer');
    expect(ringed(0), isTrue);

    await pad(tester, game, GamepadButton.dpadDown);
    expect(focused(tester, row(1)), isTrue);
    expect((ringed(0), ringed(1)), (false, true), reason: 'the ring follows the focus');
    await pad(tester, game, GamepadButton.a);
    expect(bag.countOf('bread'), 4, reason: 'A trades');
    expect(bag.countOf('gold_ingot'), 0);

    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(tester, row(0)), isTrue);
    await key(tester, LogicalKeyboardKey.enter);
    expect(bag.countOf('gold_ingot'), 1, reason: 'Enter trades');
    expect(bag.countOf('wheat'), 0);

    await key(tester, LogicalKeyboardKey.escape);
    await step(tester, game);
    expect(game.screen.value, isNull);
    game.dispose();
  });

  testWidgets('the controls: each way to play is a stop, filled, and the text scrolls under it', (tester) async {
    final game = await start(tester);
    Color fillOf(String way) =>
        tester.widget<ColoredBox>(find.descendant(of: section(way), matching: find.byType(ColoredBox)).first).color;
    await open(tester, game, 'controls');
    expect(focused(tester, section('Keyboard and mouse')), isTrue, reason: 'it opens on the first');
    expect(fillOf('Keyboard and mouse'), ScreenFocus.fill);
    await pad(tester, game, GamepadButton.dpadDown);
    expect(focused(tester, section('Gamepad')), isTrue);
    expect(fillOf('Keyboard and mouse'), Colors.transparent);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, section('Phone')), isTrue);
    await pad(tester, game, GamepadButton.dpadDown);
    expect(focused(tester, button('Back to the game')), isTrue);
    await pad(tester, game, GamepadButton.a);
    expect(game.screen.value, isNull, reason: 'A on Back closes it');

    await open(tester, game, 'controls');
    await key(tester, LogicalKeyboardKey.escape);
    await step(tester, game);
    expect(game.screen.value, isNull, reason: 'Esc too');
    game.dispose();
  });

  testWidgets('the stats and the map open on Back; a pad and the keys close them', (tester) async {
    final game = await start(tester);
    await open(tester, game, 'stats');
    expect(focused(tester, button('Back to the game')), isTrue);
    await pad(tester, game, GamepadButton.a);
    expect(game.screen.value, isNull);
    await open(tester, game, WorldMap.screen);
    expect(focused(tester, button('Back to the game')), isTrue);
    await key(tester, LogicalKeyboardKey.enter);
    expect(game.screen.value, isNull);
    game.dispose();
  });

  testWidgets('the tutorial\'s screen opens on Back; a pad skips the tutorial, the keys leave it', (tester) async {
    final game = await start(tester, tutorialDone: false);
    await open(tester, game, Tutorial.screen);
    expect(focused(tester, button('Back to the game')), isTrue, reason: 'a stray press does not skip');
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(tester, button('Skip tutorial (F6)')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.space);
    expect(game.screen.value, isNull);
    expect(Tutorial.of(game).current, isNotNull);

    await open(tester, game, Tutorial.screen);
    await pad(tester, game, GamepadButton.dpadUp);
    await pad(tester, game, GamepadButton.a);
    expect(game.screen.value, isNull);
    expect(Tutorial.of(game).current, isNull, reason: 'A on Skip skips it');
    game.dispose();
  });

  testWidgets('the playground\'s screen opens on its first button; a pad and the keys press each', (tester) async {
    final game = await start(tester);
    Iterable<String> told() => game.notices.feed.map((n) => n.text);
    await open(tester, game, Playground.screen);
    expect(focused(tester, button('Next weather (F7)')), isTrue);
    await pad(tester, game, GamepadButton.dpadDown);
    expect(focused(tester, button('Next time of day (F8)')), isTrue);
    await pad(tester, game, GamepadButton.a);
    expect(game.screen.value, isNull, reason: 'closed, so the player sees it done');
    expect(told().where((t) => t.startsWith('Time: ')), hasLength(1));

    await open(tester, game, Playground.screen);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, button('Rebuild this exhibit (F9)')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, button('Back to the game')), isTrue);
    await key(tester, LogicalKeyboardKey.escape);
    await step(tester, game);
    expect(game.screen.value, isNull);
    game.dispose();
  });
}
