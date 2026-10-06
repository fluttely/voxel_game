import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';

/// An action of a game's own (an ability, the journal, the map): its id, the
/// keys and pad buttons that press it and, for a phone, the icon of its
/// on-screen button. Declared in `VoxelGameSpec.actions`, read in the step by
/// a `GameSystem` through `VoxelGame.actions`, or opening a screen of the
/// game's own (`ScreenSpec.action`).
///
/// ```dart
/// actions: [
///   ActionSpec('journal', keys: [PhysicalKeyboardKey.keyJ], gamepad: [GamepadButton.back], touch: Icons.book),
/// ],
/// ```
class ActionSpec {
  /// The action [id], pressed by [keys] and [gamepad], and on a phone by a
  /// button showing [touch] when one is given.
  const ActionSpec(this.id, {this.keys = const [], this.gamepad = const [], this.touch})
    : assert(id != '', 'an action has an id');

  /// What `GameActions` and `ScreenSpec.action` name it by.
  final String id;

  /// The keys that press it: physical, so a layout keeps them where they are.
  final List<PhysicalKeyboardKey> keys;

  /// The pad buttons that press it.
  final List<GamepadButton> gamepad;

  /// The icon of its button among the touch controls (`TouchControls`), or
  /// null for an action a finger has no button for. The button holds the
  /// action while a finger is on it, so it reads as a press and a hold alike.
  final IconData? touch;
}
