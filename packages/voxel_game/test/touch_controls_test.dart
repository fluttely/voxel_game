import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// The kit's touch controls over a running game, on the `GameSurface`
/// `VoxelGameWidget` shows (with no HUD), whose one `Listener` feeds the input
/// map every pointer. The test surface is 800 × 600: the stick's zone is the
/// lower-left 320 × 420.
void main() {
  const spec = TouchControlsSpec.standard;

  Future<VoxelGame> start(WidgetTester tester) async {
    final game = (await tester.runAsync(() => VoxelGame.startHeadless(_spec)))!;
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
          touchControls: spec,
        ),
      ),
    );
    return game;
  }

  // A frame of the game, which the layer's selectors check, then the rebuild.
  Future<void> frame(WidgetTester tester, VoxelGame game) async {
    game.frame(1 / 60);
    await tester.pump();
  }

  double moveX(VoxelGame g) => g.input.axis(VoxelAction.moveLeft, VoxelAction.moveRight, touch: TouchAxis.x);
  double moveY(VoxelGame g) => g.input.axis(VoxelAction.moveForward, VoxelAction.moveBack, touch: TouchAxis.y);

  testWidgets('a thumb in the zone is the stick, and turns no look', (tester) async {
    final game = await start(tester);
    final input = game.input;
    final thumb = await tester.startGesture(const Offset(150, 450));
    await thumb.moveBy(Offset(spec.stickRadius * 0.5, 0));
    expect(moveX(game), closeTo(0.5, 1e-9), reason: 'the stick is centred where the thumb landed');
    expect(input.down(VoxelAction.sprint), isFalse);
    await thumb.moveBy(Offset(-spec.stickRadius * 0.5, -spec.stickRadius * 3));
    expect(moveY(game), closeTo(-1.0, 1e-9), reason: 'up the screen walks forward, clamped at the rim');
    expect(input.down(VoxelAction.sprint), isTrue, reason: 'past sprintAt it runs');
    expect(input.takeLook(0.0), Offset.zero);
    await thumb.up();
    expect(moveX(game), 0.0);
    expect(moveY(game), 0.0);
    expect(input.down(VoxelAction.sprint), isFalse);
    expect(input.justPressed(VoxelAction.use), isFalse, reason: 'the lift is not a tap on the world');
    game.dispose();
  });

  testWidgets('outside the zone a thumb is still the world\'s', (tester) async {
    final game = await start(tester);
    final thumb = await tester.startGesture(const Offset(400, 100));
    await thumb.moveBy(const Offset(60, 0));
    await thumb.up();
    expect(moveX(game), 0.0);
    expect(game.input.takeLook(0.0).dx, greaterThan(0.0));
    game.dispose();
  });

  testWidgets('jump is held while pressed', (tester) async {
    final game = await start(tester);
    final input = game.input;
    final finger = await tester.startGesture(tester.getCenter(find.byIcon(Icons.arrow_upward)));
    await tester.pump();
    expect(input.down(VoxelAction.jump), isTrue);
    expect(input.justPressed(VoxelAction.jump), isTrue);
    await finger.up();
    expect(input.down(VoxelAction.jump), isFalse);
    expect(input.justPressed(VoxelAction.use), isFalse);
    game.dispose();
  });

  testWidgets('sneak switches on and off, and letting go of every held input turns it off', (tester) async {
    final game = await start(tester);
    final input = game.input;
    await tester.tap(find.byIcon(Icons.arrow_downward));
    await frame(tester, game);
    expect(input.down(VoxelAction.sneak), isTrue);
    await frame(tester, game);
    expect(input.down(VoxelAction.sneak), isTrue, reason: 'no finger holds it');
    await tester.tap(find.byIcon(Icons.arrow_downward));
    expect(input.down(VoxelAction.sneak), isFalse);
    await tester.tap(find.byIcon(Icons.arrow_downward));
    input.releaseKeys();
    expect(input.down(VoxelAction.sneak), isFalse);
    game.dispose();
  });

  testWidgets('the view and pause buttons press once', (tester) async {
    final game = await start(tester);
    final input = game.input;
    await tester.tap(find.byIcon(Icons.cameraswitch));
    expect(input.justPressed(VoxelAction.toggleView), isTrue);
    expect(input.down(VoxelAction.toggleView), isFalse);
    await tester.tap(find.byIcon(Icons.pause));
    expect(input.justPressed(VoxelAction.pause), isTrue);
    expect(input.justPressed(VoxelAction.use), isFalse);
    game.dispose();
  });

  testWidgets('a key takes the layer off the screen, a touch puts it back', (tester) async {
    final game = await start(tester);
    final input = game.input;
    final jump = find.byIcon(Icons.arrow_upward);
    expect(jump, findsOneWidget);
    // A finger on jump when the keys take over: the layer lets go of it.
    final finger = await tester.startGesture(tester.getCenter(jump));
    input.onKey(
      FocusNode(),
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyW,
        logicalKey: LogicalKeyboardKey.keyW,
        timeStamp: Duration.zero,
      ),
    );
    await frame(tester, game);
    expect(jump, findsNothing);
    expect(input.down(VoxelAction.jump), isFalse);
    await finger.up();
    expect(input.down(VoxelAction.jump), isFalse);
    // A thumb on the stick when the keys take over: the stick lets go, and
    // what the thumb does after is nobody's.
    input.lastDevice = InputDevice.touch;
    await frame(tester, game);
    final thumb = await tester.startGesture(const Offset(150, 450));
    await thumb.moveBy(const Offset(30, 0));
    expect(moveX(game), greaterThan(0.0));
    input.lastDevice = InputDevice.keyboardMouse;
    await frame(tester, game);
    expect(moveX(game), 0.0);
    await thumb.moveBy(const Offset(30, 0));
    expect(moveX(game), 0.0);
    await thumb.up();
    await tester.tapAt(const Offset(400, 100));
    await frame(tester, game);
    expect(jump, findsOneWidget);
    // Out of gameplay (paused, a screen open) it is gone as well.
    game.gameplay = false;
    await frame(tester, game);
    expect(jump, findsNothing);
    game.gameplay = true;
    game.openScreen.value = '';
    await frame(tester, game);
    expect(jump, findsNothing);
    game.dispose();
  });
}
