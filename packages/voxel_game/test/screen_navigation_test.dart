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

/// Level grass, a quick respawn, and a screen of the game's own built of
/// plain Material buttons, with no focus code of its own.
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

/// The kit's simple screens — the game menu, the settings, the death screen,
/// a game's own — worked by a pad alone and by the keys alone, over the
/// surface `VoxelGameWidget` shows ([GameSurface] over a plain box).
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
}
