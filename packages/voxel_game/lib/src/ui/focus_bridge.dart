import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';

import 'secondary_activate_intent.dart';

/// Turns the keys and the pad presses that work a screen into Flutter's focus
/// intents, invoked where the focus is: the arrows, the dpad and the left
/// stick move it ([DirectionalFocusIntent]), Enter, Space and A press what it
/// is on ([ActivateIntent]), Esc and B back out ([DismissIntent]), and X,
/// the pad's and the key, is the other press, a right-click's
/// ([SecondaryActivateIntent]). So a widget that takes focus — a Material
/// button, a slider, a switch, a bag's slot — is worked by a pad and a
/// keyboard as it is by a pointer.
///
/// X is taken only where the focus has an action for it, so off a bag's
/// slot the key and the button are still the game's, and the key still
/// types in a text field.
///
/// A held direction repeats, after [repeatDelay] and then every
/// [repeatEvery]. The keyboard's repeat is the system's own
/// ([KeyRepeatEvent]); the pad's is the bridge's, kept from the presses and
/// releases it was handed: it reads no device state.
///
/// It works only while the focus is at or under [scope]: a pad is heard
/// wherever the focus is, and a press under another part of the app is not
/// the screen's.
class FocusBridge {
  /// A bridge for the screens under [scope].
  FocusBridge(this.scope);

  /// The node the focus must be at or under for the bridge to act.
  final FocusNode scope;

  /// How long a direction is held before it repeats.
  static const Duration repeatDelay = Duration(milliseconds: 400);

  /// How often a held direction repeats once it does.
  static const Duration repeatEvery = Duration(milliseconds: 120);

  /// How far the left stick is pushed before it points a way.
  static const double stickThreshold = 0.5;

  final Set<GamepadButton> _held = {};
  double _stickX = 0.0;
  double _stickY = 0.0;
  TraversalDirection? _stick;
  // The button, or the stick, whose direction repeats, and its timer.
  Object? _repeating;
  Timer? _repeat;

  static Intent? _ofKey(PhysicalKeyboardKey key) => switch (key) {
    PhysicalKeyboardKey.arrowUp => const DirectionalFocusIntent(TraversalDirection.up),
    PhysicalKeyboardKey.arrowDown => const DirectionalFocusIntent(TraversalDirection.down),
    PhysicalKeyboardKey.arrowLeft => const DirectionalFocusIntent(TraversalDirection.left),
    PhysicalKeyboardKey.arrowRight => const DirectionalFocusIntent(TraversalDirection.right),
    PhysicalKeyboardKey.enter || PhysicalKeyboardKey.numpadEnter || PhysicalKeyboardKey.space => const ActivateIntent(),
    PhysicalKeyboardKey.escape => const DismissIntent(),
    PhysicalKeyboardKey.keyX => const SecondaryActivateIntent(),
    _ => null,
  };

  static Intent? _ofButton(GamepadButton button) => switch (button) {
    GamepadButton.dpadUp => const DirectionalFocusIntent(TraversalDirection.up),
    GamepadButton.dpadDown => const DirectionalFocusIntent(TraversalDirection.down),
    GamepadButton.dpadLeft => const DirectionalFocusIntent(TraversalDirection.left),
    GamepadButton.dpadRight => const DirectionalFocusIntent(TraversalDirection.right),
    GamepadButton.a => const ActivateIntent(),
    GamepadButton.b => const DismissIntent(),
    GamepadButton.x => const SecondaryActivateIntent(),
    _ => null,
  };

  /// A key event: handled when it is one of the screen's keys going down (or
  /// repeating), ignored otherwise, its release included.
  KeyEventResult onKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final intent = _ofKey(event.physicalKey);
    if (intent == null || !_takes(intent)) return KeyEventResult.ignored;
    _invoke(intent);
    return KeyEventResult.handled;
  }

  /// A pad event: true when the bridge took it, which only a press of one of
  /// the screen's buttons is. A release and the stick's motion are seen and
  /// not taken, so whoever records the pad still sees it let go and resting.
  bool onPad(NormalizedGamepadEvent event) {
    final button = event.button;
    if (button != null) {
      final intent = _ofButton(button);
      if (intent == null) return false;
      if (event.value == 0) {
        _held.remove(button);
        _letGo(button);
        return false;
      }
      if (!_inside || !_takes(intent)) return false;
      // Already down: the press was taken, and so is its change of pressure.
      if (!_held.add(button)) return true;
      _invoke(intent);
      if (intent is DirectionalFocusIntent) _hold(button, intent);
      return true;
    }
    switch (event.axis) {
      case GamepadAxis.leftStickX:
        _stickX = event.value;
      case GamepadAxis.leftStickY:
        _stickY = event.value;
      default:
        return false;
    }
    final way = _stickWay();
    if (way == _stick) return false;
    _stick = way;
    _letGo(_stickSource);
    if (way != null && _inside) {
      final intent = DirectionalFocusIntent(way);
      _invoke(intent);
      _hold(_stickSource, intent);
    }
    return false;
  }

  /// Forgets what is held and stops a repeat: the screen it worked closed or
  /// gave way to another.
  void reset() {
    _held.clear();
    _stick = null;
    _letGo(_repeating);
  }

  /// Stops a repeat for good.
  void dispose() => reset();

  static const Object _stickSource = #stick;

  // The stick's up is positive y.
  TraversalDirection? _stickWay() {
    if (_stickX.abs() < stickThreshold && _stickY.abs() < stickThreshold) return null;
    if (_stickX.abs() >= _stickY.abs()) return _stickX > 0 ? TraversalDirection.right : TraversalDirection.left;
    return _stickY > 0 ? TraversalDirection.up : TraversalDirection.down;
  }

  bool get _inside {
    final focus = FocusManager.instance.primaryFocus;
    return focus != null && (identical(focus, scope) || focus.ancestors.contains(scope));
  }

  // The other press is the screen's only where the focus has an action for
  // it; every other intent is the screen's wherever the focus is.
  bool _takes(Intent intent) {
    if (intent is! SecondaryActivateIntent) return true;
    if (!_inside) return false;
    final action = Actions.maybeFind<SecondaryActivateIntent>(FocusManager.instance.primaryFocus!.context!);
    return action != null && action.isEnabled(intent);
  }

  void _invoke(Intent intent) {
    if (!_inside) return;
    Actions.maybeInvoke(FocusManager.instance.primaryFocus!.context!, intent);
  }

  void _hold(Object source, DirectionalFocusIntent intent) {
    _repeat?.cancel();
    _repeating = source;
    _repeat = Timer(repeatDelay, () {
      _invoke(intent);
      _repeat = Timer.periodic(repeatEvery, (_) => _invoke(intent));
    });
  }

  void _letGo(Object? source) {
    if (source == null || !identical(source, _repeating)) return;
    _repeat?.cancel();
    _repeat = null;
    _repeating = null;
  }
}
