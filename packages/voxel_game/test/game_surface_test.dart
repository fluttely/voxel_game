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

/// The surface `VoxelGameWidget` shows once the game has loaded, over a plain
/// box instead of the `SceneView`: the `Listener`, the capture, the screen and
/// the stack are the widget's own.
void main() {
  Future<VoxelGame> start(WidgetTester tester, {TouchControlsSpec? touchControls}) async {
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
          touchControls: touchControls,
        ),
      ),
    );
    return game;
  }

  testWidgets('the first press takes the pointer and is nothing else; the next is the world\'s', (tester) async {
    final game = await start(tester);
    final input = game.input;
    expect(input.wantCapture, isFalse);
    await tester.tapAt(const Offset(100, 100));
    expect(input.wantCapture, isTrue);
    expect(input.justPressed(VoxelAction.use), isFalse);
    expect(input.justPressed(VoxelAction.attack), isFalse);
    await tester.tapAt(const Offset(100, 100));
    expect(input.justPressed(VoxelAction.use), isTrue);
    game.dispose();
  });

  testWidgets('a screen frees the pointer, lets go of what was held, keeps its presses, and gives the pointer back', (
    tester,
  ) async {
    final game = await start(tester);
    final input = game.input;
    await input.capture();
    input.touchToggle(VoxelAction.sneak);
    expect(input.touchHeld(VoxelAction.sneak), isTrue);
    game.openScreen(const BagScreen());
    await tester.pump();
    expect(find.byType(InventoryScreen), findsOneWidget);
    expect(input.wantCapture, isFalse);
    expect(input.touchHeld(VoxelAction.sneak), isFalse, reason: 'the switched-on sneak is let go');
    // A press on the screen is the screen's: it neither captures nor uses.
    await tester.tapAt(const Offset(10, 10));
    expect(input.wantCapture, isFalse);
    expect(input.justPressed(VoxelAction.use), isFalse);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(game.screen.value, isNull);
    expect(find.byType(InventoryScreen), findsNothing);
    expect(input.wantCapture, isTrue);
    game.dispose();
  });

  testWidgets('the touch controls are mounted only when given', (tester) async {
    final bare = await start(tester);
    expect(find.byType(TouchControls), findsNothing);
    expect(find.byType(DefaultHud), findsOneWidget);
    bare.dispose();
    final touch = await start(tester, touchControls: TouchControlsSpec.standard);
    expect(find.byType(TouchControls), findsOneWidget);
    touch.dispose();
  });

  testWidgets('the keys reach the game', (tester) async {
    final game = await start(tester);
    final input = game.input..lastDevice = InputDevice.touch;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    expect(input.lastDevice, InputDevice.keyboardMouse);
    expect(input.down(VoxelAction.moveForward), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    expect(input.down(VoxelAction.moveForward), isFalse);
    game.dispose();
  });
}
