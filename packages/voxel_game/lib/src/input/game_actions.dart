import '../spec/action_spec.dart';
import 'input_map.dart';

/// A game's own actions (`VoxelGameSpec.actions`), held and pressed by the
/// keys and pad buttons the kit's [InputMap] records, by their on-screen
/// buttons, or from code. Read by a `GameSystem` in the step, as the player
/// reads the kit's: `game.actions.justPressed('journal')`. Like the kit's,
/// they are read while `VoxelGame.gameplay` by whatever plays (a screen open
/// over the world has its own controls).
///
/// The step forgets the presses after every step ([endTick]), and a screen
/// opening lets go of what a button held ([releaseHeld]), as the kit's input
/// does.
class GameActions {
  /// The actions [specs], reading the keys and pad buttons [input] records.
  GameActions(List<ActionSpec> specs, this._input) : _specs = {for (final a in specs) a.id: a};

  final Map<String, ActionSpec> _specs;
  final InputMap<Object> _input;
  final Set<String> _held = {};
  final Set<String> _pressed = {};

  /// Every action's id, in the order declared.
  Iterable<String> get ids => _specs.keys;

  ActionSpec _spec(String id) {
    final spec = _specs[id];
    if (spec == null) throw ArgumentError.value(id, 'id', 'the spec declares no such action');
    return spec;
  }

  /// Whether [id] is held: a key, a pad button, its on-screen button or code.
  /// Throws for an action the spec does not declare.
  bool down(String id) {
    final spec = _spec(id);
    return _held.contains(id) || spec.keys.any(_input.keyDown) || spec.gamepad.any(_input.padDown);
  }

  /// Whether [id] was pressed since the last [endTick]. Throws for an action
  /// the spec does not declare.
  bool justPressed(String id) {
    final spec = _spec(id);
    return _pressed.contains(id) || spec.keys.any(_input.keyPressed) || spec.gamepad.any(_input.padPressed);
  }

  /// Holds or lets go of [id], from its on-screen button or from code; taking
  /// it also counts as a press for this step.
  void hold(String id, bool down) {
    _spec(id);
    if (down) {
      if (_held.add(id)) _pressed.add(id);
    } else {
      _held.remove(id);
    }
  }

  /// Presses [id] once, from code.
  void tap(String id) {
    _spec(id);
    _pressed.add(id);
  }

  /// Whether [hold] is holding [id]: what its button draws itself lit by.
  bool held(String id) {
    _spec(id);
    return _held.contains(id);
  }

  /// Lets go of every held action (a screen opened over the buttons that
  /// held them, or focus left), as `InputMap.releaseKeys` does for the kit's.
  void releaseHeld() => _held.clear();

  /// Forgets this step's presses; the game calls it after every step.
  void endTick() => _pressed.clear();
}
