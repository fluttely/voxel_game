import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:voxel_game/voxel_game.dart';

/// The input map read by a finger. A touch reports itself as the primary
/// button, so it is never read as one: it is a gesture that says three
/// different things depending on what it does — lift in place, stay put, or
/// travel — and an on-screen control writes the rest through the same
/// [InputMap.down] / [InputMap.justPressed] / [InputMap.axis] a key goes
/// through.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InputMap<VoxelAction> map() => InputMap<VoxelAction>(VoxelAction.defaultBindings);

  PointerDownEvent touchDown(int id, [Offset at = const Offset(400, 300)]) =>
      PointerDownEvent(pointer: id, kind: PointerDeviceKind.touch, position: at);
  PointerMoveEvent touchMove(int id, Offset to, Offset delta) =>
      PointerMoveEvent(pointer: id, kind: PointerDeviceKind.touch, position: to, delta: delta);
  PointerUpEvent touchUp(int id, [Offset at = const Offset(400, 300)]) =>
      PointerUpEvent(pointer: id, kind: PointerDeviceKind.touch, position: at);

  group('a finger on the world', () {
    test('lifting in place presses the secondary button: use what is aimed at', () {
      final input = map();
      input.onPointerDown(touchDown(1));
      input.onPointerUp(touchUp(1));
      expect(input.justPressed(VoxelAction.use), isTrue);
      expect(input.justPressed(VoxelAction.attack), isFalse);
      input.dispose();
    });

    test('lifting in place presses the primary one when the game says so', () {
      final input = map()..touchTapPrimary = true;
      input.onPointerDown(touchDown(1));
      input.onPointerUp(touchUp(1));
      expect(input.justPressed(VoxelAction.attack), isTrue);
      expect(input.justPressed(VoxelAction.use), isFalse);
      input.dispose();
    });

    test('travelling is the camera, and nothing else', () async {
      final input = map()..wantCapture = true;
      input.onPointerDown(touchDown(1));
      input.onPointerMove(touchMove(1, const Offset(460, 300), const Offset(60, 0)));
      // Long past the delay: a finger that is steering never starts mining.
      await Future<void>.delayed(input.mineDelay * 2);
      expect(input.down(VoxelAction.attack), isFalse);
      input.onPointerUp(touchUp(1, const Offset(460, 300)));
      expect(input.justPressed(VoxelAction.attack), isFalse);
      expect(input.justPressed(VoxelAction.use), isFalse);
      // The drag is the look, in radians, and it drains once.
      expect(input.takeLook(0.0).dx, closeTo(60 * input.lookSensitivity, 1e-9));
      expect(input.takeLook(0.0), Offset.zero);
      input.dispose();
    });

    test('a turn from code is a rate, taken by the time each look covers', () {
      final input = map()..turn(0.5, -0.25);
      expect(input.takeLook(0.1).dx, closeTo(0.05, 1e-12));
      expect(input.takeLook(0.02).dy, closeTo(-0.005, 1e-12));
      input.turn(0, 0);
      expect(input.takeLook(1.0), Offset.zero);
      input.dispose();
    });

    test('the look scale speeds a drag and a look from code, never a turn', () {
      final input = map()
        ..wantCapture = true
        ..lookScale = 2.0;
      input.onPointerDown(touchDown(1));
      input.onPointerMove(touchMove(1, const Offset(460, 300), const Offset(60, 0)));
      expect(input.takeLook(0.0).dx, closeTo(120 * input.lookSensitivity, 1e-9));
      input.look(10, 0);
      expect(input.takeLook(0.0).dx, closeTo(20 * input.lookSensitivity, 1e-9));
      input.turn(0.5, 0);
      expect(input.takeLook(0.1).dx, closeTo(0.05, 1e-12), reason: 'a turn is a rate the code chose');
      input.dispose();
    });

    test('staying put holds the primary button, and is not also a tap', () async {
      final input = map();
      input.onPointerDown(touchDown(1));
      expect(input.down(VoxelAction.attack), isFalse, reason: 'the gesture is still undecided');
      await Future<void>.delayed(input.mineDelay * 2);
      expect(input.down(VoxelAction.attack), isTrue);
      // A thumb may nudge the view without letting go of the dig.
      input.onPointerMove(touchMove(1, const Offset(460, 300), const Offset(60, 0)));
      expect(input.down(VoxelAction.attack), isTrue);
      input.onPointerUp(touchUp(1, const Offset(460, 300)));
      expect(input.down(VoxelAction.attack), isFalse);
      expect(input.justPressed(VoxelAction.attack), isFalse);
      expect(input.justPressed(VoxelAction.use), isFalse);
      input.dispose();
    });

    test('a touch the system takes away decides nothing', () async {
      final input = map();
      input.onPointerDown(touchDown(1));
      input.onPointerCancel(
        PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.touch, position: const Offset(400, 300)),
      );
      await Future<void>.delayed(input.mineDelay * 2);
      expect(input.down(VoxelAction.attack), isFalse);
      expect(input.justPressed(VoxelAction.use), isFalse);
      input.dispose();
    });

    test('a mouse is still a mouse: a press is a press where it lands', () {
      final input = map();
      input.onPointerDown(PointerDownEvent(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton));
      expect(input.down(VoxelAction.attack), isTrue);
      expect(input.justPressed(VoxelAction.attack), isTrue);
      input.onPointerUp(const PointerUpEvent(kind: PointerDeviceKind.mouse));
      expect(input.down(VoxelAction.attack), isFalse);
      input.dispose();
    });
  });

  group('on-screen controls write what everything else reads', () {
    test('the stick is the left stick', () {
      final input = map();
      double x() => input.axis(VoxelAction.moveLeft, VoxelAction.moveRight, touch: TouchAxis.x);
      double y() => input.axis(VoxelAction.moveForward, VoxelAction.moveBack, touch: TouchAxis.y);
      expect(x(), 0.0);
      expect(y(), 0.0);
      input.touchMove(1.0, -1.0);
      expect(x(), 1.0);
      // Forward is -1 on this axis, the sense moveForward has.
      expect(y(), -1.0);
      input.touchMove(0.0, 0.0);
      expect(x(), 0.0);
      input.dispose();
    });

    test('a button held is down, and pressed for exactly one step', () {
      final input = map();
      input.setTouchHeld(VoxelAction.jump, true);
      expect(input.down(VoxelAction.jump), isTrue);
      expect(input.justPressed(VoxelAction.jump), isTrue);
      input.endTick();
      expect(input.down(VoxelAction.jump), isTrue, reason: 'the finger is still on it');
      expect(input.justPressed(VoxelAction.jump), isFalse, reason: 'one press, one shot');
      input.setTouchHeld(VoxelAction.jump, false);
      expect(input.down(VoxelAction.jump), isFalse);
      input.dispose();
    });

    test('a slot is read like the digit row, once', () {
      final input = map();
      expect(input.digitPressed(), -1);
      input.touchDigit(4);
      expect(input.digitPressed(), 4);
      input.endTick();
      expect(input.digitPressed(), -1);
      input.dispose();
    });

    test('a screen opening takes every held input with it', () {
      final input = map();
      input.setTouchHeld(VoxelAction.jump, true);
      input.touchMove(0.0, -1.0);
      input.hold(VoxelAction.sprint, true);
      input.onKey(
        FocusNode(),
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
          timeStamp: Duration.zero,
        ),
      );
      expect(input.down(VoxelAction.moveForward), isTrue);
      input.releaseKeys();
      expect(input.down(VoxelAction.jump), isFalse);
      expect(input.down(VoxelAction.sprint), isFalse);
      expect(input.down(VoxelAction.moveForward), isFalse);
      expect(input.axis(VoxelAction.moveForward, VoxelAction.moveBack, touch: TouchAxis.y), 0.0);
      input.dispose();
    });

    test('a switch stays on across steps, and a screen opening turns it off', () {
      final input = map();
      input.touchToggle(VoxelAction.sneak);
      expect(input.touchHeld(VoxelAction.sneak), isTrue);
      expect(input.justPressed(VoxelAction.sneak), isTrue);
      for (var i = 0; i < 3; i++) {
        input.endTick();
      }
      expect(input.down(VoxelAction.sneak), isTrue, reason: 'no finger holds it, the switch does');
      expect(input.justPressed(VoxelAction.sneak), isFalse);
      input.touchToggle(VoxelAction.sneak);
      expect(input.down(VoxelAction.sneak), isFalse);
      input.touchToggle(VoxelAction.sneak);
      input.releaseKeys();
      expect(input.touchHeld(VoxelAction.sneak), isFalse);
      expect(input.down(VoxelAction.sneak), isFalse);
      input.dispose();
    });

    test('a one-shot is seen by exactly one step, and never held', () {
      final input = map();
      input.touchPress(VoxelAction.drop);
      expect(input.justPressed(VoxelAction.drop), isTrue);
      expect(input.down(VoxelAction.drop), isFalse);
      expect(input.touchHeld(VoxelAction.drop), isFalse);
      input.endTick();
      expect(input.justPressed(VoxelAction.drop), isFalse);
      input.dispose();
    });

    test('a finger a control claimed neither looks, mines nor taps', () async {
      final input = map()..wantCapture = true;
      // A tap on the control.
      input.claimTouch(1);
      input.onPointerDown(touchDown(1));
      input.onPointerUp(touchUp(1));
      expect(input.justPressed(VoxelAction.use), isFalse);
      expect(input.justPressed(VoxelAction.attack), isFalse);
      // A hold, then a drag off it.
      input.claimTouch(2);
      input.onPointerDown(touchDown(2));
      await Future<void>.delayed(input.mineDelay * 2);
      expect(input.down(VoxelAction.attack), isFalse);
      input.onPointerMove(touchMove(2, const Offset(460, 300), const Offset(60, 0)));
      expect(input.takeLook(0.0), Offset.zero);
      input.onPointerUp(touchUp(2, const Offset(460, 300)));
      expect(input.justPressed(VoxelAction.use), isFalse);
      // The claim ends with the lift: the same pointer id on the world is the
      // world's again.
      input.onPointerDown(touchDown(1));
      input.onPointerUp(touchUp(1));
      expect(input.justPressed(VoxelAction.use), isTrue);
      input.dispose();
    });

    test('a claim a cancel ended is forgotten too', () {
      final input = map();
      input.claimTouch(1);
      input.onPointerDown(touchDown(1));
      input.onPointerCancel(
        PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.touch, position: const Offset(400, 300)),
      );
      input.onPointerDown(touchDown(1));
      input.onPointerUp(touchUp(1));
      expect(input.justPressed(VoxelAction.use), isTrue);
      input.dispose();
    });
  });

  group('the last device', () {
    NormalizedGamepadEvent pad({GamepadButton? button, GamepadAxis? axis, required double value}) =>
        NormalizedGamepadEvent(
          gamepadId: 'pad',
          timestamp: 0,
          button: button,
          axis: axis,
          value: value,
          rawEvent: GamepadEvent(gamepadId: 'pad', timestamp: 0, type: KeyType.button, key: 'k', value: value),
        );

    test('each device takes it with the event it was handed', () {
      final input = map()..lastDevice = InputDevice.keyboardMouse;
      input.onPointerDown(touchDown(1));
      expect(input.lastDevice, InputDevice.touch);
      input.onKey(
        FocusNode(),
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
          timeStamp: Duration.zero,
        ),
      );
      expect(input.lastDevice, InputDevice.keyboardMouse);
      input.onPad(pad(button: GamepadButton.a, value: 1.0));
      expect(input.lastDevice, InputDevice.gamepad);
      input.onPointerDown(PointerDownEvent(pointer: 2, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton));
      expect(input.lastDevice, InputDevice.keyboardMouse);
      input.onPad(pad(axis: GamepadAxis.leftStickX, value: 0.8));
      expect(input.lastDevice, InputDevice.gamepad);
      // A finger that lands on a control is still a finger.
      input.claimTouch(3);
      input.onPointerDown(touchDown(3));
      expect(input.lastDevice, InputDevice.touch);
      input.dispose();
    });

    test('a phone starts in touch, a desktop on the keys', () {
      for (final (platform, device) in [
        (TargetPlatform.android, InputDevice.touch),
        (TargetPlatform.iOS, InputDevice.touch),
        (TargetPlatform.macOS, InputDevice.keyboardMouse),
        (TargetPlatform.windows, InputDevice.keyboardMouse),
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final input = map();
        expect(input.lastDevice, device, reason: '$platform');
        input.dispose();
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('a resting pad does not take it', () {
      final input = map()..lastDevice = InputDevice.touch;
      input.onPad(pad(axis: GamepadAxis.leftStickX, value: input.deadzone * 0.5));
      input.onPad(pad(button: GamepadButton.a, value: 0.0));
      expect(input.lastDevice, InputDevice.touch);
      input.dispose();
    });
  });
}
