import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';

import 'input_map.dart';

/// The kit's actions: what its player and its screens read, bound by
/// `VoxelGameSpec.bindings` ([defaultBindings] unless a game moves one with
/// [InputBindings.rebind]). A game's own actions are not here: it declares
/// them as `VoxelGameSpec.actions` and reads them through `GameActions`.
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
  pause,

  /// Take off or land, in creative only (`PlayerSpec.creative`): flying, jump
  /// rises and sneak sinks (F, dpad right).
  fly,

  /// Held in the air with an item that glides in the bag (`ItemType.glider`):
  /// the fall slows and the body sails toward the look (G, dpad up).
  glide,

  /// The next hotbar slot, the last one around to the first (right bumper);
  /// the wheel and the digit keys pick a slot on a keyboard, a finger taps
  /// one.
  hotbarNext,

  /// The slot before, the first one around to the last (left bumper). A game
  /// that wants one bumper for itself may unbind this one and keep
  /// [hotbarNext]: on a nine-slot bar, stepping one way is enough.
  hotbarPrevious;

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
      fly: [PhysicalKeyboardKey.keyF],
      glide: [PhysicalKeyboardKey.keyG],
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
      fly: GamepadButton.dpadRight,
      glide: GamepadButton.dpadUp,
      hotbarNext: GamepadButton.rightBumper,
      hotbarPrevious: GamepadButton.leftBumper,
    },
    triggers: {attack: TriggerBinding.right, use: TriggerBinding.left},
  );
}
