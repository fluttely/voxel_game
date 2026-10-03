import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:vector_math/vector_math.dart' show Vector2, Vector3;
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
  BlockType('dirt', color: 0x8A5E3B, hardness: 0.5, tool: 'shovel'),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel'),
  BlockType.liquid('water', color: 0x3366CC),
];

const _journal = ActionSpec(
  'journal',
  keys: [PhysicalKeyboardKey.keyJ],
  gamepad: [GamepadButton.back],
  touch: Icons.book,
);
const _dash = ActionSpec('dash', keys: [PhysicalKeyboardKey.keyR], touch: Icons.bolt);

Widget _journalScreen(BuildContext context, VoxelGame game) => const SizedBox.shrink();

VoxelGameSpec _spec({
  PlayerSpec player = const PlayerSpec(),
  List<ActionSpec> actions = const [_journal, _dash],
  InputBindings<VoxelAction> bindings = VoxelAction.defaultBindings,
  Map<String, ScreenSpec> screens = const {'journal': ScreenSpec(_journalScreen, action: 'journal')},
  List<GameSystem> systems = const [],
}) => VoxelGameSpec(
  blocks: _blocks,
  world: WorldGenSpec(
    terrain: const TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  items: const [ItemType('glider', color: 0xD04A30, stack: 1, glider: Glider(speed: 10.0, fall: 1.5))],
  sky: SkySpec.alwaysDay,
  player: player,
  actions: actions,
  bindings: bindings,
  screens: screens,
  systems: systems,
);

Future<VoxelGame> _start(VoxelGameSpec spec) async {
  final game = await VoxelGame.startHeadless(spec);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue, reason: 'the spawn chunk loads and the player stands on it');
  return game;
}

/// One fixed step, letting the chunk jobs land after it.
Future<void> _step(VoxelGame game) async {
  game.step(1 / 60);
  await Future<void>.delayed(Duration.zero);
}

/// [seconds] of frames, which also stream the world in around the player.
Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

void _key(VoxelGame game, PhysicalKeyboardKey key, {bool down = true}) => game.input.onKey(
  FocusNode(),
  down
      ? KeyDownEvent(physicalKey: key, logicalKey: LogicalKeyboardKey.keyA, timeStamp: Duration.zero)
      : KeyUpEvent(physicalKey: key, logicalKey: LogicalKeyboardKey.keyA, timeStamp: Duration.zero),
);

NormalizedGamepadEvent _pad(GamepadButton button, double value) => NormalizedGamepadEvent(
  gamepadId: 'pad',
  timestamp: 0,
  button: button,
  value: value,
  rawEvent: GamepadEvent(gamepadId: 'pad', timestamp: 0, type: KeyType.button, key: 'k', value: value),
);

/// A system that writes down what the game's actions read in each step.
class _Reader implements GameSystem {
  final List<(bool, bool)> dash = [];

  @override
  void tick(VoxelGame game, double dt) => dash.add((game.actions.justPressed('dash'), game.actions.down('dash')));
}

void main() {
  group('a game\'s own actions', () {
    test('a key, a pad button and code press them; a system reads them in the step', () async {
      final reader = _Reader();
      final game = await _start(_spec(systems: [reader]));
      _key(game, PhysicalKeyboardKey.keyR);
      await _step(game);
      await _step(game);
      _key(game, PhysicalKeyboardKey.keyR, down: false);
      await _step(game);
      expect(reader.dash, [(true, true), (false, true), (false, false)], reason: 'pressed once, held until let go');
      expect(game.input.justPressed(VoxelAction.attack), isFalse, reason: 'R is no key of the kit\'s');
      game.input.onPad(_pad(GamepadButton.back, 1.0));
      expect(game.actions.justPressed('journal'), isTrue);
      expect(game.actions.down('journal'), isTrue);
      game.input.onPad(_pad(GamepadButton.back, 0.0));
      game.actions.tap('dash');
      expect(game.actions.justPressed('dash'), isTrue);
      expect(game.actions.down('dash'), isFalse, reason: 'a tap presses and holds nothing');
      game.actions.hold('dash', true);
      game.actions.releaseHeld();
      expect(game.actions.down('dash'), isFalse);
      expect(() => game.actions.down('map'), throwsArgumentError, reason: 'no action of that id is declared');
      game.dispose();
    });

    test('an action opens its screen and closes it again; pause closes it too', () async {
      final game = await _start(_spec());
      _key(game, PhysicalKeyboardKey.keyJ);
      await _step(game);
      expect(game.screen.value, const DeclaredScreen('journal'));
      _key(game, PhysicalKeyboardKey.keyJ, down: false);
      await _step(game);
      expect(game.screen.value, const DeclaredScreen('journal'), reason: 'letting go is no second press');
      _key(game, PhysicalKeyboardKey.keyJ);
      await _step(game);
      expect(game.screen.value, isNull);
      game.actions.tap('journal');
      await _step(game);
      game.input.tap(VoxelAction.pause);
      await _step(game);
      expect(game.screen.value, isNull);
      game.gameplay = false;
      game.actions.tap('journal');
      await _step(game);
      expect(game.screen.value, isNull, reason: 'out of gameplay no action opens a screen');
      game.dispose();
    });

    test('a key the kit already binds is refused until the game moves the kit\'s action off it', () async {
      const view = ActionSpec('map', keys: [PhysicalKeyboardKey.f5]);
      expect(() => _spec(actions: [view]).checkActions(), throwsArgumentError, reason: 'F5 turns the view');
      final freed = VoxelAction.defaultBindings.rebind(
        keys: {
          VoxelAction.toggleView: [PhysicalKeyboardKey.keyV],
        },
      );
      final game = await _start(_spec(actions: [view], bindings: freed, screens: const {}));
      _key(game, PhysicalKeyboardKey.f5);
      expect(game.actions.justPressed('map'), isTrue);
      expect(game.input.justPressed(VoxelAction.toggleView), isFalse);
      _key(game, PhysicalKeyboardKey.keyV);
      expect(game.input.justPressed(VoxelAction.toggleView), isTrue);
      game.dispose();
    });

    test('the spec refuses two actions of one id, one key or button twice, and a screen on no action', () {
      expect(() => _spec(actions: [_dash, _dash]).checkActions(), throwsArgumentError);
      const r = ActionSpec('ability', keys: [PhysicalKeyboardKey.keyR]);
      expect(() => _spec(actions: [_dash, r]).checkActions(), throwsArgumentError);
      const pad = ActionSpec('jumpy', gamepad: [GamepadButton.a]);
      expect(() => _spec(actions: [pad]).checkActions(), throwsArgumentError, reason: 'A jumps');
      expect(
        () => _spec(actions: [_dash]).checkActions(),
        throwsArgumentError,
        reason: 'the journal screen opens on an action not declared',
      );
      expect(
        () => _spec(
          screens: const {
            'journal': ScreenSpec(_journalScreen, action: 'journal'),
            'book': ScreenSpec(_journalScreen, action: 'journal'),
          },
        ).checkActions(),
        throwsArgumentError,
      );
      _spec().checkActions();
    });

    test('rebind replaces what it names and keeps the rest', () {
      final b = VoxelAction.defaultBindings.rebind(
        keys: {
          VoxelAction.fly: [PhysicalKeyboardKey.f5],
          VoxelAction.drop: [],
        },
        gamepad: {VoxelAction.glide: null, VoxelAction.fly: GamepadButton.x},
      );
      expect(b.keys[VoxelAction.fly], [PhysicalKeyboardKey.f5]);
      expect(b.keys.containsKey(VoxelAction.drop), isFalse, reason: 'an empty list unbinds the keys');
      expect(b.keys[VoxelAction.jump], [PhysicalKeyboardKey.space]);
      expect(b.gamepad.containsKey(VoxelAction.glide), isFalse, reason: 'null unbinds the button');
      expect(b.gamepad[VoxelAction.fly], GamepadButton.x);
      expect(b.mouse, VoxelAction.defaultBindings.mouse);
    });
  });

  group('fly', () {
    test('a creative player takes off and lands with a press: no gravity, jump rises, sneak sinks', () async {
      final game = await _start(_spec(player: const PlayerSpec(creative: true)));
      final p = game.player;
      game.input.tap(VoxelAction.fly);
      await _step(game);
      expect(p.flying, isTrue);
      game.input.hold(VoxelAction.jump, true);
      await _run(game, 0.5);
      game.input.hold(VoxelAction.jump, false);
      final up = p.position.y;
      await _run(game, 1.0);
      expect(p.position.y, closeTo(up, 1e-6), reason: 'a flyer hangs where it stopped');
      expect(up, greaterThan(24.0), reason: 'half a second of rising off the ground at 21');
      game.input.hold(VoxelAction.sneak, true);
      await _run(game, 0.25);
      game.input.hold(VoxelAction.sneak, false);
      expect(p.position.y, lessThan(up - 1.0));
      game.input.hold(VoxelAction.moveForward, true);
      await _run(game, 1.0);
      game.input.hold(VoxelAction.moveForward, false);
      final flat = Vector2(p.velocity.x, p.velocity.z).length;
      expect(flat, closeTo(p.spec.flySpeed, 0.5), reason: 'it drifts up to flySpeed');
      game.input.tap(VoxelAction.fly);
      await _step(game);
      expect(p.flying, isFalse);
      await _run(game, 3.0);
      expect(p.onFloor, isTrue, reason: 'landed, it falls');
      game.dispose();
    });

    test('a survival player does not fly, by key or by code', () async {
      final game = await _start(_spec());
      final p = game.player;
      game.input.tap(VoxelAction.fly);
      await _step(game);
      expect(p.flying, isFalse);
      expect(() => p.flying = true, throwsStateError);
      game.dispose();
    });
  });

  group('glide', () {
    Future<VoxelGame> aloft({required bool glider}) async {
      final game = await _start(_spec());
      final p = game.player;
      if (glider) p.inventory.add('glider', 1);
      p.position = Vector3(p.position.x, 30, p.position.z);
      p.motor.resetFall();
      return game;
    }

    test('held in the air with a glider in the bag, the fall slows and the body sails ahead', () async {
      final game = await aloft(glider: true);
      final p = game.player;
      expect(p.glider!.fall, 1.5);
      game.input.hold(VoxelAction.glide, true);
      await _run(game, 0.5);
      expect(p.gliding, isTrue);
      for (var i = 0; i < 120; i++) {
        await _run(game, 1 / 60);
        expect(p.velocity.y, greaterThanOrEqualTo(-1.5 - 1e-5), reason: 'the glider\'s own sink');
      }
      final flat = Vector2(p.velocity.x, p.velocity.z).length;
      expect(flat, closeTo(10.0, 0.5), reason: 'toward the look at the glider\'s speed, with no move held');
      for (var i = 0; i < 60 * 10 && !p.onFloor; i++) {
        await _run(game, 1 / 60);
      }
      game.input.hold(VoxelAction.glide, false);
      expect(p.onFloor, isTrue);
      expect(p.hp, p.spec.hp, reason: 'a glide down never lands hurt');
      game.dispose();
    });

    test('without a glider glide does nothing', () async {
      final game = await aloft(glider: false);
      final p = game.player;
      expect(p.glider, isNull);
      game.input.hold(VoxelAction.glide, true);
      await _run(game, 0.4);
      expect(p.gliding, isFalse);
      expect(p.velocity.y, lessThan(-5.0));
      game.dispose();
    });
  });

  group('touch', () {
    Future<VoxelGame> surface(WidgetTester tester, VoxelGameSpec spec) async {
      final game = (await tester.runAsync(() => VoxelGame.startHeadless(spec)))!;
      game.spawner.enabled = false;
      game.input
        ..wantCapture = true
        ..lastDevice = InputDevice.touch;
      await tester.pumpWidget(
        MaterialApp(
          home: GameSurface(
            game: game,
            world: const ColoredBox(color: Colors.black),
            hud: (context, game) => const SizedBox.shrink(),
            touchControls: TouchControlsSpec.standard,
          ),
        ),
      );
      return game;
    }

    testWidgets('a game\'s action with an icon gets a button that holds it', (tester) async {
      final game = await surface(tester, _spec());
      final finger = await tester.startGesture(tester.getCenter(find.byIcon(Icons.bolt)));
      await tester.pump();
      expect(game.actions.justPressed('dash'), isTrue);
      expect(game.actions.down('dash'), isTrue);
      expect(game.input.justPressed(VoxelAction.use), isFalse, reason: 'the button claims its finger');
      await finger.up();
      expect(game.actions.down('dash'), isFalse);
      expect(find.byIcon(Icons.book), findsOneWidget);
      game.dispose();
    });

    testWidgets('a screen opening lets go of what a button held', (tester) async {
      final game = await surface(tester, _spec());
      await tester.startGesture(tester.getCenter(find.byIcon(Icons.bolt)));
      await tester.pump();
      game.openScreen(const PauseScreen());
      await tester.pump();
      expect(game.actions.down('dash'), isFalse);
      game.dispose();
    });

    testWidgets('fly is a button in creative only, glide while the bag holds a glider', (tester) async {
      final survival = await surface(tester, _spec());
      expect(find.byIcon(Icons.flight_takeoff), findsNothing);
      expect(find.byIcon(Icons.paragliding), findsNothing);
      survival.player.inventory.add('glider', 1);
      survival.frame(1 / 60);
      await tester.pump();
      final finger = await tester.startGesture(tester.getCenter(find.byIcon(Icons.paragliding)));
      await tester.pump();
      expect(survival.input.down(VoxelAction.glide), isTrue);
      await finger.up();
      expect(survival.input.down(VoxelAction.glide), isFalse);
      survival.dispose();
      final creative = await surface(tester, _spec(player: const PlayerSpec(creative: true)));
      await tester.tap(find.byIcon(Icons.flight_takeoff));
      expect(creative.input.justPressed(VoxelAction.fly), isTrue);
      creative.dispose();
    });
  });
}
