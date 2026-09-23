import 'package:voxel_game_minecraft/src/game/input.dart';
import 'package:voxel_game_minecraft/src/ui/hud.dart';
import 'package:voxel_game_minecraft/src/ui/touch_controls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage 44: a phone plays it. The on-screen controls write to [GameInput] and
/// nothing else, so the simulation reads a thumb exactly as it reads a key or a
/// pad; and a finger on the world says three different things depending on what
/// it does — lift in place, stay put, or travel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A touch on the world, at [at] by default.
  PointerDownEvent touchDown(int id, [Offset at = const Offset(400, 300)]) =>
      PointerDownEvent(pointer: id, kind: PointerDeviceKind.touch, position: at);
  PointerMoveEvent touchMove(int id, Offset to, Offset delta) =>
      PointerMoveEvent(pointer: id, kind: PointerDeviceKind.touch, position: to, delta: delta);
  PointerUpEvent touchUp(int id, [Offset at = const Offset(400, 300)]) =>
      PointerUpEvent(pointer: id, kind: PointerDeviceKind.touch, position: at);

  group('the controls write to the same input everything else reads', () {
    test('the stick is the left stick', () {
      final input = GameInput();
      expect(input.moveAxisX(), 0.0);
      expect(input.moveAxisY(), 0.0);
      input.touchMove(1.0, -1.0);
      expect(input.moveAxisX(), 1.0);
      // Forward is -1 on this axis, the sense moveForward has.
      expect(input.moveAxisY(), -1.0);
      input.touchMove(0.0, 0.0);
      expect(input.moveAxisX(), 0.0);
      input.dispose();
    });

    test('a button held is down, and pressed for exactly one tick', () {
      final input = GameInput();
      input.setTouchHeld(GameAction.jump, true);
      expect(input.down(GameAction.jump), isTrue);
      expect(input.justPressed(GameAction.jump), isTrue);
      input.endTick();
      expect(input.down(GameAction.jump), isTrue, reason: 'the finger is still on it');
      expect(input.justPressed(GameAction.jump), isFalse, reason: 'one press, one shot');
      input.setTouchHeld(GameAction.jump, false);
      expect(input.down(GameAction.jump), isFalse);
      input.dispose();
    });

    test('a hotbar slot is read like the digit row, once', () {
      final input = GameInput();
      expect(input.hotbarPressed(), -1);
      input.touchHotbar(4);
      expect(input.hotbarPressed(), 4);
      input.endTick();
      expect(input.hotbarPressed(), -1);
      input.dispose();
    });

    test('a screen opening takes every held action with it', () {
      final input = GameInput();
      input.setTouchHeld(GameAction.jump, true);
      input.touchMove(0.0, -1.0);
      input.releaseKeys();
      expect(input.down(GameAction.jump), isFalse);
      expect(input.moveAxisY(), 0.0);
      input.dispose();
    });
  });

  group('a finger on the world', () {
    test('lifting in place uses what the crosshair points at', () {
      final input = GameInput();
      input.onPointerDown(touchDown(1));
      input.onPointerUp(touchUp(1));
      expect(input.justPressed(GameAction.use), isTrue);
      expect(input.justPressed(GameAction.attack), isFalse);
      input.dispose();
    });

    test('lifting in place swings when a creature is the nearest thing', () {
      final input = GameInput();
      input.touchTapAttacks = true;
      input.onPointerDown(touchDown(1));
      input.onPointerUp(touchUp(1));
      expect(input.justPressed(GameAction.attack), isTrue);
      expect(input.justPressed(GameAction.use), isFalse);
      input.dispose();
    });

    test('travelling is the camera, and nothing else', () async {
      final input = GameInput();
      input.wantCapture = true;
      input.onPointerDown(touchDown(1));
      input.onPointerMove(touchMove(1, const Offset(460, 300), const Offset(60, 0)));
      // Long past the delay: a finger that is steering never starts mining.
      await Future<void>.delayed(GameInput.touchMineDelay * 2);
      expect(input.down(GameAction.attack), isFalse);
      input.onPointerUp(touchUp(1, const Offset(460, 300)));
      expect(input.justPressed(GameAction.attack), isFalse);
      expect(input.justPressed(GameAction.use), isFalse);
      input.dispose();
    });

    test('staying put mines, and mining is not also a tap', () async {
      final input = GameInput();
      input.onPointerDown(touchDown(1));
      expect(input.down(GameAction.attack), isFalse, reason: 'the gesture is still undecided');
      await Future<void>.delayed(GameInput.touchMineDelay * 2);
      expect(input.down(GameAction.attack), isTrue);
      // A thumb may nudge the view without letting go of the dig.
      input.onPointerMove(touchMove(1, const Offset(460, 300), const Offset(60, 0)));
      expect(input.down(GameAction.attack), isTrue);
      input.onPointerUp(touchUp(1, const Offset(460, 300)));
      expect(input.down(GameAction.attack), isFalse);
      expect(input.justPressed(GameAction.attack), isFalse);
      expect(input.justPressed(GameAction.use), isFalse);
      input.dispose();
    });

    test('a touch the system takes away decides nothing', () async {
      final input = GameInput();
      input.onPointerDown(touchDown(1));
      input.onPointerCancel(PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.touch, position: const Offset(400, 300)));
      await Future<void>.delayed(GameInput.touchMineDelay * 2);
      expect(input.down(GameAction.attack), isFalse);
      expect(input.justPressed(GameAction.use), isFalse);
      input.dispose();
    });
  });

  group('the layer on the screen', () {
    Future<GameInput> pumpControls(WidgetTester tester) async {
      final input = GameInput();
      await tester.pumpWidget(MaterialApp(home: TouchControls(input: input)));
      return input;
    }

    testWidgets('jump is held while the finger is on it', (tester) async {
      final input = await pumpControls(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.arrow_upward)));
      await tester.pump();
      expect(input.down(GameAction.jump), isTrue);
      await gesture.up();
      await tester.pump();
      expect(input.down(GameAction.jump), isFalse);
      input.dispose();
    });

    testWidgets('sneak latches, so a thumb is free for the rest', (tester) async {
      final input = await pumpControls(tester);
      await tester.tap(find.byIcon(Icons.arrow_downward));
      await tester.pump();
      expect(input.down(GameAction.sneak), isTrue);
      await tester.tap(find.byIcon(Icons.arrow_downward));
      await tester.pump();
      expect(input.down(GameAction.sneak), isFalse);
      input.dispose();
    });

    testWidgets('the bag opens the inventory', (tester) async {
      final input = await pumpControls(tester);
      await tester.tap(find.byIcon(Icons.backpack));
      expect(input.justPressed(GameAction.inventory), isTrue);
      input.dispose();
    });

    testWidgets('a hotbar slot is chosen where the HUD drew it', (tester) async {
      final input = await pumpControls(tester);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.tapAt(Hud.hotbarSlotRect(size, 3).center);
      expect(input.hotbarPressed(), 3);
      input.dispose();
    });

    testWidgets('the stick walks, and sprints at the rim', (tester) async {
      final input = await pumpControls(tester);
      final centre = tester.getCenter(find.byType(TouchControls).last);
      final stick = Offset(
        TouchControls.stickInset.dx,
        centre.dy * 2 - TouchControls.stickInset.dy,
      );
      final gesture = await tester.startGesture(stick);
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      expect(input.moveAxisY(), lessThan(0.0), reason: 'pushed up is forward');
      expect(input.down(GameAction.sprint), isFalse, reason: 'a walk, not a run');
      await gesture.moveBy(const Offset(0, -TouchControls.stickRadius));
      await tester.pump();
      expect(input.moveAxisY(), -1.0);
      expect(input.down(GameAction.sprint), isTrue, reason: 'pushed to the rim is a run');
      await gesture.up();
      await tester.pump();
      expect(input.moveAxisY(), 0.0);
      expect(input.down(GameAction.sprint), isFalse);
      input.dispose();
    });

    testWidgets('the layer leaving the screen lets go of what it held', (tester) async {
      final input = await pumpControls(tester);
      await tester.startGesture(tester.getCenter(find.byIcon(Icons.arrow_upward)));
      await tester.pump();
      expect(input.down(GameAction.jump), isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(input.down(GameAction.jump), isFalse);
      input.dispose();
    });
  });
}
