import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';

import 'input_map.dart';

/// The kit's actions: what its player reads. A game with more makes its own
/// enum and its own [InputMap].
enum VoxelAction {
  /// Walk forward (W, left stick).
  moveForward,

  /// Walk back (S).
  moveBack,

  /// Strafe left (A).
  moveLeft,

  /// Strafe right (D).
  moveRight,

  /// Jump; swim up; climb a ladder (Space, A).
  jump,

  /// Run (Shift, left stick press).
  sprint,

  /// Walk slowly without falling off edges; climb down (Ctrl, B).
  sneak,

  /// Mine, hit (left mouse, right trigger).
  attack,

  /// Place, use (right mouse, left trigger).
  use,

  /// First or third person (V, right stick press).
  toggleView,

  /// Drop the held item (Q, dpad down).
  drop,

  /// The inventory (E, Y).
  inventory,

  /// Pause; free the mouse (Escape, start).
  pause;

  /// The default bindings: the usual WASD keys and an Xbox / PlayStation pad.
  static const InputBindings<VoxelAction> defaultBindings = InputBindings(
    keys: {
      moveForward: [PhysicalKeyboardKey.keyW],
      moveBack: [PhysicalKeyboardKey.keyS],
      moveLeft: [PhysicalKeyboardKey.keyA],
      moveRight: [PhysicalKeyboardKey.keyD],
      jump: [PhysicalKeyboardKey.space],
      sprint: [PhysicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftRight],
      sneak: [PhysicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlRight],
      toggleView: [PhysicalKeyboardKey.keyV, PhysicalKeyboardKey.f5],
      drop: [PhysicalKeyboardKey.keyQ],
      inventory: [PhysicalKeyboardKey.keyE],
      pause: [PhysicalKeyboardKey.escape],
    },
    mouse: {attack: MouseBinding.left, use: MouseBinding.right},
    gamepad: {
      jump: GamepadButton.a,
      sneak: GamepadButton.b,
      inventory: GamepadButton.y,
      sprint: GamepadButton.leftStick,
      toggleView: GamepadButton.rightStick,
      drop: GamepadButton.dpadDown,
      pause: GamepadButton.start,
    },
    triggers: {attack: TriggerBinding.right, use: TriggerBinding.left},
  );
}
