import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';
import 'package:voxel_game/voxel_game.dart' show InputBindings, InputMap, MouseBinding, TouchAxis, TriggerBinding;

/// Every action the game reads. Keys are physical (WASD stays WASD on any
/// layout), matching the Godot POC's input map.
enum GameAction {
  moveForward,
  moveBack,
  moveLeft,
  moveRight,
  jump,
  sprint,
  sneak,
  attack,
  use,
  inventory,
  dropItem,
  toggleView,
  ability,
  ability2,
  glide,
  interact,
  pause,
  eat,
  map,
  debugHud,
  screenshot,
  fly,
  dodge,
  journal,
  skipTutorial, // stage 30
  cycleWeather, // stage 33: playground F7
  cycleTime, // stage 33: playground F8
  rebuildExhibit, // stage 33: playground F9
}

/// Dawnforge's own actions over the kit's [InputMap]: the key, mouse, pad and
/// touch tables this game binds, and nothing else. Every read — [down],
/// [justPressed], [moveAxisX], [hotbarPressed], [takeLookDelta] — is the kit's
/// own, so a finger, a key, a pad button and a probe all arrive through one
/// implementation (`CL-003`).
///
/// The one unit this class does not share with the kit is the look: [InputMap]
/// answers in radians, and `Player` has owned the pixels-to-radians multiply
/// (its `mouseSensitivity`, times the settings slider) since stage 4. So the
/// map is built with a sensitivity of 1 — it hands back the pixels it was
/// given — and the right stick's turn rate is pushed through the same mirror
/// constant, which is exactly what this file did before it delegated.
class GameInput {
  GameInput() {
    _map.attachDevices();
  }

  // A PS5/Xbox-style pad next to WASD (parity, not a second control scheme):
  // left stick moves, right stick looks, triggers are the mouse buttons.
  // Face/shoulder/dpad buttons cover the rest; F-key dev/probe tools
  // (debugHud, screenshot, fly, skipTutorial, the playground F7-F9) stay
  // keyboard-only on purpose, same as `_keys` leaves attack/use to the mouse.
  static const Map<GameAction, GamepadButton> _gamepadButtons = {
    GameAction.jump: GamepadButton.a,
    GameAction.sneak: GamepadButton.b,
    GameAction.interact: GamepadButton.x,
    GameAction.inventory: GamepadButton.y,
    GameAction.ability: GamepadButton.leftBumper,
    GameAction.ability2: GamepadButton.rightBumper,
    GameAction.sprint: GamepadButton.leftStick,
    GameAction.toggleView: GamepadButton.rightStick,
    GameAction.glide: GamepadButton.dpadUp,
    GameAction.dropItem: GamepadButton.dpadDown,
    GameAction.eat: GamepadButton.dpadLeft,
    GameAction.dodge: GamepadButton.dpadRight,
    GameAction.pause: GamepadButton.start,
    GameAction.map: GamepadButton.back,
    GameAction.journal: GamepadButton.touchpad,
  };

  // A finger is the camera, not a mouse button. A touch that travels further
  // than this many logical pixels is a look drag and swings nothing; one that
  // lifts where it landed is a tap, and one that stays down mines
  // ([touchMineDelay]).
  static const double _tapSlop = 12.0;

  // Minecraft's own reading of a finger on the world: one that stays put this
  // long is mining, and goes on mining until it lifts. Shorter than this and
  // an ordinary tap starts a dig it never meant; longer and the pickaxe feels
  // stuck. A finger that travels first is a look drag and never mines.
  static const Duration touchMineDelay = Duration(milliseconds: 180);

  static const double _stickDeadzone = 0.2;
  // Radians/second of yaw or pitch at full stick deflection; divided by the
  // mouse's own sensitivity constant so one settings slider covers both.
  static const double _gamepadLookRadiansPerSecond = 3.0;
  // Mirrors Player.mouseSensitivity (rad/pixel) — kept local to avoid an
  // input.dart <-> player.dart import cycle; update both if either changes.
  static const double _mouseSensitivityMirror = 0.0022;

  static const Map<GameAction, List<PhysicalKeyboardKey>> _keys = {
    GameAction.moveForward: [PhysicalKeyboardKey.keyW],
    GameAction.moveBack: [PhysicalKeyboardKey.keyS],
    GameAction.moveLeft: [PhysicalKeyboardKey.keyA],
    GameAction.moveRight: [PhysicalKeyboardKey.keyD],
    GameAction.jump: [PhysicalKeyboardKey.space],
    GameAction.sprint: [PhysicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftRight],
    GameAction.sneak: [PhysicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlRight],
    GameAction.inventory: [PhysicalKeyboardKey.keyE, PhysicalKeyboardKey.tab],
    GameAction.dropItem: [PhysicalKeyboardKey.keyQ],
    GameAction.toggleView: [PhysicalKeyboardKey.keyV],
    GameAction.ability: [PhysicalKeyboardKey.keyR],
    // Stage 23: Q, the same physical key Godot binds to both drop_item and
    // ability2 (a press does both there too).
    GameAction.ability2: [PhysicalKeyboardKey.keyQ],
    GameAction.glide: [PhysicalKeyboardKey.keyG],
    GameAction.interact: [PhysicalKeyboardKey.keyF],
    GameAction.pause: [PhysicalKeyboardKey.escape],
    GameAction.eat: [PhysicalKeyboardKey.keyH],
    GameAction.map: [PhysicalKeyboardKey.keyM],
    GameAction.debugHud: [PhysicalKeyboardKey.f1],
    GameAction.screenshot: [PhysicalKeyboardKey.f2],
    GameAction.fly: [PhysicalKeyboardKey.f5],
    GameAction.dodge: [PhysicalKeyboardKey.altLeft, PhysicalKeyboardKey.altRight],
    GameAction.journal: [PhysicalKeyboardKey.keyJ],
    GameAction.skipTutorial: [PhysicalKeyboardKey.f6],
    GameAction.cycleWeather: [PhysicalKeyboardKey.f7],
    GameAction.cycleTime: [PhysicalKeyboardKey.f8],
    GameAction.rebuildExhibit: [PhysicalKeyboardKey.f9],
  };

  /// What presses what: the keyboard table above, the two mouse buttons (the
  /// finger's tap and hold land on these same two), and the pad.
  static const InputBindings<GameAction> bindings = InputBindings(
    keys: _keys,
    mouse: {GameAction.attack: MouseBinding.left, GameAction.use: MouseBinding.right},
    gamepad: _gamepadButtons,
    triggers: {GameAction.attack: TriggerBinding.right, GameAction.use: TriggerBinding.left},
  );

  final InputMap<GameAction> _map = InputMap<GameAction>(
    bindings,
    // Pixels in, pixels out: Player owns the sensitivity multiply.
    lookSensitivity: 1.0,
    stickTurnRate: _gamepadLookRadiansPerSecond / _mouseSensitivityMirror,
    deadzone: _stickDeadzone,
    tapSlop: _tapSlop,
    mineDelay: touchMineDelay,
  );

  /// Whether the game wants the mouse captured (Godot's MOUSE_MODE_CAPTURED).
  bool get wantCapture => _map.wantCapture;
  set wantCapture(bool v) => _map.wantCapture = v;

  /// An unrequested release (focus loss): the game notices and opens its pause
  /// menu.
  bool get captureLost => _map.captureLost;
  set captureLost(bool v) => _map.captureLost = v;

  bool get pointerLockSupported => _map.pointerLockSupported;
  bool get isCaptured => _map.isCaptured;

  Future<void> capture() => _map.capture();

  Future<void> release() => _map.release();

  KeyEventResult onKey(FocusNode node, KeyEvent event) => _map.onKey(node, event);

  /// What the crosshair is nearest to, written by [Player] every time it
  /// re-aims: true while a creature is the closest thing in reach. A tap on
  /// the world swings at a creature and uses anything else (a block placed, a
  /// door opened, a chest looked into) — Minecraft's split, and the reason a
  /// phone needs no separate attack button.
  bool get touchTapAttacks => _map.touchTapPrimary;
  set touchTapAttacks(bool v) => _map.touchTapPrimary = v;

  /// Released by an on-screen button, and by the screens: a menu that opens
  /// takes the controls off the screen, and an action still held by a button
  /// that is no longer there would never come back up.
  void releaseKeys() => _map.releaseKeys();

  /// The on-screen stick, in the left stick's own units: x right, y forward
  /// (-1 pushes away from the player, the sense [GameAction.moveForward]
  /// has). The widget writes it on every move and zeroes it on the lift.
  void touchMove(double x, double y) => _map.touchMove(x, y);

  /// An on-screen button taking or letting go of an action. Taking it also
  /// counts as a press for this tick, which is what a one-shot action
  /// (inventory, pause) reads.
  void setTouchHeld(GameAction a, bool held) => _map.setTouchHeld(a, held);

  /// A finger on a hotbar slot, read like the digit row.
  void touchHotbar(int slot) => _map.touchDigit(slot);

  /// Probe hook: hold or release an action as if it were typed, so a
  /// screenshot run can drive the simulation without a keyboard.
  void probeHold(GameAction a, bool down) => _map.hold(a, down);

  void onPointerDown(PointerDownEvent e) => _map.onPointerDown(e);

  void onPointerUp(PointerUpEvent e) => _map.onPointerUp(e);

  /// A touch the system took away (a system gesture, a call). It decided
  /// nothing, so it swings nothing — it is only forgotten.
  void onPointerCancel(PointerCancelEvent e) => _map.onPointerCancel(e);

  void onPointerMove(PointerMoveEvent e) => _map.onPointerMove(e);

  void onPointerSignal(PointerSignalEvent e) => _map.onPointerSignal(e);

  bool down(GameAction a) => _map.down(a);

  bool justPressed(GameAction a) => _map.justPressed(a);

  /// The left stick's X axis (-1 left, 1 right), combined with A/D and the
  /// on-screen stick so every device drives the same wish vector (parity).
  double moveAxisX() =>
      _map.axis(GameAction.moveLeft, GameAction.moveRight, stick: GamepadAxis.leftStickX, touch: TouchAxis.x);

  /// The left stick's Y axis, combined with W/S. Stick up (+1) means
  /// forward, same sense as [GameAction.moveForward] setting inputY to -1.
  double moveAxisY() => _map.axis(
        GameAction.moveForward,
        GameAction.moveBack,
        stick: GamepadAxis.leftStickY,
        invertStick: true,
        touch: TouchAxis.y,
      );

  /// The hotbar digit pressed this tick (0..8), or -1.
  int hotbarPressed() => _map.digitPressed();

  /// Wheel steps this tick: positive = down.
  int takeWheel() => _map.takeWheel();

  /// The mouse motion since the previous tick (in logical pixels), plus the
  /// right stick's own turn for this tick converted to the same unit so
  /// [Player]'s one `mouseSensitivity` multiply covers both devices. The
  /// stick is a held deflection rather than a discrete delta, so it needs
  /// [dt] to integrate into a per-tick amount; the mouse path does not.
  Offset takeLookDelta(double dt) => _map.takeLook(dt);

  /// Forgets the one-shot presses; call at the end of every tick.
  void endTick() => _map.endTick();

  void dispose() => _map.dispose();
}
