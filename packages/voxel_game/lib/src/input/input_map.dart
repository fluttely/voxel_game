import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';
import 'package:pointer_lock/pointer_lock.dart';

/// The mouse buttons an action can be bound to.
enum MouseBinding {
  /// The primary button.
  left,

  /// The secondary button.
  right,

  /// The middle button.
  middle,
}

/// The two analog triggers, bound as buttons (a press past half way).
enum TriggerBinding {
  /// L2 / LT.
  left,

  /// R2 / RT.
  right,
}

/// Which half of the on-screen stick an [InputMap.axis] call also reads.
enum TouchAxis {
  /// Pushed right is positive.
  x,

  /// Pushed away from the player is negative, the sense a "walk forward"
  /// action has.
  y,
}

/// What presses what: physical keys (layout-independent, so WASD stays
/// WASD), mouse buttons, gamepad buttons and triggers, per action.
class InputBindings<A extends Object> {
  /// Bindings; an action may have any mix of the four.
  const InputBindings({this.keys = const {}, this.mouse = const {}, this.gamepad = const {}, this.triggers = const {}});

  /// Keys per action.
  final Map<A, List<PhysicalKeyboardKey>> keys;

  /// Mouse buttons per action.
  final Map<A, MouseBinding> mouse;

  /// Gamepad buttons per action.
  final Map<A, GamepadButton> gamepad;

  /// Gamepad triggers per action.
  final Map<A, TriggerBinding> triggers;
}

/// Held and just-pressed actions, the wheel and the look motion (mouse and
/// right stick), read by the simulation once per step and cleared by
/// [endTick]. Generic over the game's own action type; `VoxelAction` is the
/// kit's.
///
/// Feed it from a widget ([onKey], the pointer callbacks) and [attachDevices];
/// or drive it from code with [hold] (tests, bots, cutscenes).
///
/// **A finger is a first-class device, not a mouse.** A touch reports itself
/// as the primary button, so it is read as a gesture instead: one that lifts
/// where it landed is a tap and presses the mouse button [touchTapPrimary]
/// names; one that stays put for [mineDelay] holds the primary button until it
/// lifts; one that travels further than [tapSlop] is the look and presses
/// nothing. On-screen controls write the rest through [touchMove],
/// [setTouchHeld] and [touchDigit], which fold into the same [down] /
/// [justPressed] / [axis] / [digitPressed] a key or a pad goes through, so
/// nothing downstream can tell a thumb from a key.
class InputMap<A extends Object> {
  /// A map over [bindings]. [lookSensitivity] turns a pixel of mouse motion
  /// into radians; a full stick turns [stickTurnRate] radians a second.
  /// [tapSlop] and [mineDelay] are what a finger on the world is measured
  /// against.
  InputMap(
    this.bindings, {
    this.lookSensitivity = 0.0022,
    this.stickTurnRate = 3.0,
    this.deadzone = 0.2,
    this.tapSlop = 12.0,
    this.mineDelay = const Duration(milliseconds: 180),
  });

  /// What presses what.
  final InputBindings<A> bindings;

  /// Radians per pixel of mouse motion.
  double lookSensitivity;

  /// Radians a second at full right-stick deflection.
  double stickTurnRate;

  /// Stick deflection below this is ignored.
  final double deadzone;

  /// How far a finger may travel, in logical pixels, and still be a tap. Past
  /// it the touch is a look drag and swings nothing.
  final double tapSlop;

  /// How long a finger must stay where it landed before it holds the primary
  /// button down. Shorter and an ordinary tap starts a dig it never meant;
  /// longer and the tool feels stuck.
  final Duration mineDelay;

  static const double _triggerThreshold = 0.5;

  final Set<PhysicalKeyboardKey> _held = {};
  final Set<PhysicalKeyboardKey> _pressed = {};
  final Set<MouseBinding> _mouseHeld = {};
  final Set<MouseBinding> _mousePressed = {};
  final Set<A> _scriptHeld = {};
  final Set<A> _scriptPressed = {};
  final NormalizedGamepadState _pad = NormalizedGamepadState();
  final Set<GamepadButton> _padPressed = {};
  final Set<TriggerBinding> _triggerHeld = {};
  final Set<TriggerBinding> _triggerPressed = {};
  StreamSubscription<NormalizedGamepadEvent>? _padSub;
  StreamSubscription<CaptureState>? _lockSub;
  int _wheel = 0;
  Offset _drag = Offset.zero;
  Offset _scriptLook = Offset.zero;
  // Where each live finger landed, and which of them have already travelled
  // past [tapSlop] and so became look drags.
  final Map<int, Offset> _touchOrigin = {};
  final Set<int> _touchDragged = {};
  // The fingers that held still long enough to hold the primary button, and
  // the timers still waiting to decide (one per live finger).
  final Set<int> _touchMining = {};
  final Map<int, Timer> _touchMineTimers = {};
  // The on-screen controls' half: what a button holds, what it pressed this
  // step, where the stick is pushed and which digit a finger chose.
  final Set<A> _touchHeld = {};
  final Set<A> _touchPressed = {};
  double _touchMoveX = 0.0;
  double _touchMoveY = 0.0;
  int _touchDigit = -1;

  /// Whether the game wants the mouse captured (looking around).
  bool wantCapture = false;

  /// Set when the capture was lost without being asked (focus left the
  /// window): a game opens its pause menu on it.
  bool captureLost = false;

  /// What a tap on the world means, written by the game every time it re-aims:
  /// true presses the primary mouse button (the swing at whatever the
  /// crosshair is nearest to), false presses the secondary (place, open, use).
  /// It is the mouse's own split, and the reason a phone needs no separate
  /// attack button.
  bool touchTapPrimary = false;

  /// Listens to gamepads and to pointer-lock state; a widget calls it once.
  void attachDevices() {
    _padSub ??= Gamepads.normalizedEvents.listen(_onPad);
    _lockSub ??= PointerLock.instance.onStateChanged.listen((state) {
      if (state == CaptureState.released && wantCapture) {
        captureLost = true;
        wantCapture = false;
      }
    });
  }

  /// Stops listening.
  void dispose() {
    _padSub?.cancel();
    _lockSub?.cancel();
    for (final t in _touchMineTimers.values) {
      t.cancel();
    }
    _touchMineTimers.clear();
  }

  /// Whether the platform locks the pointer (desktop); elsewhere a drag looks.
  bool get pointerLockSupported => PointerLock.instance.isSupported;

  /// Whether the game is looking around right now: the pointer is locked, or
  /// the platform has no lock to give and the game asked for one anyway.
  bool get isCaptured => wantCapture && (PointerLock.instance.isCaptured || !pointerLockSupported);

  /// Locks the pointer for looking around.
  Future<void> capture() async {
    wantCapture = true;
    captureLost = false;
    _drag = Offset.zero;
    if (pointerLockSupported) await PointerLock.instance.capture();
  }

  /// Frees the pointer (a menu opened).
  Future<void> release() async {
    wantCapture = false;
    if (pointerLockSupported) await PointerLock.instance.release();
  }

  /// A key event from a `Focus`; every key is handled while playing so the
  /// platform does not beep at held keys.
  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    final key = event.physicalKey;
    if (event is KeyDownEvent) {
      _held.add(key);
      _pressed.add(key);
    } else if (event is KeyUpEvent) {
      _held.remove(key);
    }
    return KeyEventResult.handled;
  }

  /// Forgets every held input (focus lost, or a screen that opened over the
  /// controls): a key, a mouse button, a scripted hold and everything the
  /// on-screen controls were holding. A button that leaves the screen gets no
  /// lift event, so the action it held would otherwise never come back up.
  void releaseKeys() {
    _held.clear();
    _mouseHeld.clear();
    _scriptHeld.clear();
    _touchHeld.clear();
    _touchMoveX = 0.0;
    _touchMoveY = 0.0;
    for (final t in _touchMineTimers.values) {
      t.cancel();
    }
    _touchMineTimers.clear();
    _touchMining.clear();
  }

  /// The on-screen stick, in the left stick's own units: x right, y forward
  /// (-1 pushes away from the player). A control writes it on every move and
  /// zeroes it on the lift; [axis] adds it when asked for a [TouchAxis].
  void touchMove(double x, double y) {
    _touchMoveX = x.clamp(-1.0, 1.0);
    _touchMoveY = y.clamp(-1.0, 1.0);
  }

  /// An on-screen button taking or letting go of [action]. Taking it also
  /// counts as a press for this step, which is what a one-shot action reads.
  void setTouchHeld(A action, bool held) {
    if (held) {
      if (_touchHeld.add(action)) _touchPressed.add(action);
    } else {
      _touchHeld.remove(action);
    }
  }

  /// A finger on an on-screen slot, read by [digitPressed] like the digit row:
  /// 0..8 for the nine digits.
  void touchDigit(int index) {
    assert(index >= 0 && index < 9, 'digit out of range: $index');
    _touchDigit = index;
  }

  /// A finger that stayed where it landed holds the primary button, and goes
  /// on holding it while it is down — even once it starts steering the view,
  /// the way a thumb nudges the camera mid-dig.
  void _beginTouchMining(int pointer) {
    _touchMineTimers.remove(pointer);
    if (!_touchOrigin.containsKey(pointer)) return;
    _touchMining.add(pointer);
  }

  void _forgetTouch(int pointer) {
    _touchOrigin.remove(pointer);
    _touchDragged.remove(pointer);
    _touchMining.remove(pointer);
    _touchMineTimers.remove(pointer)?.cancel();
  }

  static Set<MouseBinding> _buttons(int mask) => {
    if (mask & kPrimaryMouseButton != 0) MouseBinding.left,
    if (mask & kSecondaryMouseButton != 0) MouseBinding.right,
    if (mask & kMiddleMouseButton != 0) MouseBinding.middle,
  };

  /// A pointer press. A touch decides nothing yet: the gesture is undecided
  /// until the finger moves, lifts, or outstays [mineDelay].
  void onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _touchOrigin[e.pointer] = e.position;
      _touchMineTimers[e.pointer] = Timer(mineDelay, () => _beginTouchMining(e.pointer));
      return;
    }
    final b = _buttons(e.buttons);
    _mouseHeld.addAll(b);
    _mousePressed.addAll(b);
  }

  /// A pointer release. A finger that neither travelled nor stayed is a tap,
  /// and taps the same one-shot a mouse button does ([touchTapPrimary]).
  void onPointerUp(PointerUpEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      final origin = _touchOrigin.remove(e.pointer);
      final dragged = _touchDragged.remove(e.pointer);
      final mined = _touchMining.remove(e.pointer);
      _touchMineTimers.remove(e.pointer)?.cancel();
      // A null origin means the touch began over an open screen, where it was
      // never the game's to read.
      if (origin != null && !dragged && !mined) {
        _mousePressed.add(touchTapPrimary ? MouseBinding.left : MouseBinding.right);
      }
      return;
    }
    _mouseHeld.removeWhere((b) => !_buttons(e.buttons).contains(b));
  }

  /// A touch the system took away (a system gesture, a call). It decided
  /// nothing, so it presses nothing — it is only forgotten.
  void onPointerCancel(PointerCancelEvent e) => _forgetTouch(e.pointer);

  /// A pointer motion: the look, where the pointer cannot be locked, and
  /// wherever a finger is doing the dragging (a finger never locks).
  void onPointerMove(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      final origin = _touchOrigin[e.pointer];
      if (origin == null) return;
      if ((e.position - origin).distance > tapSlop && _touchDragged.add(e.pointer)) {
        // The finger moved before it was old enough to hold the button, so it
        // never will: this one is steering. A finger already holding it keeps
        // holding it, and steers as well.
        _touchMineTimers.remove(e.pointer)?.cancel();
      }
      if (_touchDragged.contains(e.pointer) && wantCapture) _drag += e.delta;
      return;
    }
    if (!pointerLockSupported && wantCapture) _drag += e.delta;
  }

  /// A wheel turn.
  void onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) _wheel += e.scrollDelta.dy.sign.toInt();
  }

  void _onPad(NormalizedGamepadEvent event) {
    final button = event.button;
    final was = button != null && _pad.isPressed(button);
    _pad.update(event);
    if (button != null && !was && _pad.isPressed(button)) _padPressed.add(button);
    for (final (t, b, a) in [
      (TriggerBinding.left, GamepadButton.leftTrigger, GamepadAxis.leftTrigger),
      (TriggerBinding.right, GamepadButton.rightTrigger, GamepadAxis.rightTrigger),
    ]) {
      final down = _pad.isPressed(b) || _pad.axisValue(a) > _triggerThreshold;
      if (down && !_triggerHeld.contains(t)) _triggerPressed.add(t);
      down ? _triggerHeld.add(t) : _triggerHeld.remove(t);
    }
  }

  /// Holds or releases [action] from code; a hold also counts as a press.
  void hold(A action, bool down) {
    if (down) {
      if (_scriptHeld.add(action)) _scriptPressed.add(action);
    } else {
      _scriptHeld.remove(action);
    }
  }

  /// Presses [action] once from code.
  void tap(A action) => _scriptPressed.add(action);

  /// Adds a look motion from code, in pixels.
  void look(double dx, double dy) => _scriptLook += Offset(dx, dy);

  /// Whether [action] is held.
  bool down(A action) {
    if (_scriptHeld.contains(action) || _touchHeld.contains(action)) return true;
    for (final k in bindings.keys[action] ?? const <PhysicalKeyboardKey>[]) {
      if (_held.contains(k)) return true;
    }
    final m = bindings.mouse[action];
    // A finger that stayed put holds the primary button: the same action a
    // mouse's own left button holds, whichever one the game bound to it.
    if (m != null && (_mouseHeld.contains(m) || (m == MouseBinding.left && _touchMining.isNotEmpty))) return true;
    final g = bindings.gamepad[action];
    if (g != null && _pad.isPressed(g)) return true;
    final t = bindings.triggers[action];
    return t != null && _triggerHeld.contains(t);
  }

  /// Whether [action] was pressed since the last [endTick].
  bool justPressed(A action) {
    if (_scriptPressed.contains(action) || _touchPressed.contains(action)) return true;
    for (final k in bindings.keys[action] ?? const <PhysicalKeyboardKey>[]) {
      if (_pressed.contains(k)) return true;
    }
    final m = bindings.mouse[action];
    if (m != null && _mousePressed.contains(m)) return true;
    final g = bindings.gamepad[action];
    if (g != null && _padPressed.contains(g)) return true;
    final t = bindings.triggers[action];
    return t != null && _triggerPressed.contains(t);
  }

  /// -1..1 from [negative] and [positive] held, plus [stick] past the
  /// deadzone ([invertStick] flips it: a stick's up is -y on screen) and
  /// [touch], the on-screen stick's own half ([touchMove]).
  double axis(A negative, A positive, {GamepadAxis? stick, bool invertStick = false, TouchAxis? touch}) {
    var v = 0.0;
    if (down(negative)) v -= 1;
    if (down(positive)) v += 1;
    if (stick != null) {
      final s = _pad.axisValue(stick);
      if (s.abs() > deadzone) v += invertStick ? -s : s;
    }
    if (touch != null) v += touch == TouchAxis.x ? _touchMoveX : _touchMoveY;
    return v.clamp(-1.0, 1.0);
  }

  /// The digit key 1..9 pressed this step as 0..8, or the slot a finger chose
  /// ([touchDigit]); -1 for neither.
  int digitPressed() {
    if (_touchDigit >= 0) return _touchDigit;
    const digits = [
      PhysicalKeyboardKey.digit1, PhysicalKeyboardKey.digit2, PhysicalKeyboardKey.digit3, //
      PhysicalKeyboardKey.digit4, PhysicalKeyboardKey.digit5, PhysicalKeyboardKey.digit6,
      PhysicalKeyboardKey.digit7, PhysicalKeyboardKey.digit8, PhysicalKeyboardKey.digit9,
    ];
    for (var i = 0; i < digits.length; i++) {
      if (_pressed.contains(digits[i])) return i;
    }
    return -1;
  }

  /// Wheel steps since the last call; positive is down.
  int takeWheel() {
    final w = _wheel;
    _wheel = 0;
    return w;
  }

  /// The look since the last call, in radians (yaw right, pitch down
  /// positive): the mouse (or drag) motion plus [dt] of right stick.
  Offset takeLook(double dt) {
    var d = _scriptLook;
    _scriptLook = Offset.zero;
    // The drag accumulator drains unconditionally: a finger fills it even on a
    // platform that does lock the pointer, and a delta left in it would arrive
    // as a jump the next time the view is captured.
    d += _drag;
    _drag = Offset.zero;
    if (pointerLockSupported && wantCapture) d += PointerLock.instance.takeDelta();
    var rad = d * lookSensitivity;
    final gx = _pad.axisValue(GamepadAxis.rightStickX), gy = _pad.axisValue(GamepadAxis.rightStickY);
    if (gx.abs() > deadzone || gy.abs() > deadzone) rad += Offset(gx, -gy) * (stickTurnRate * dt);
    return rad;
  }

  /// Forgets this step's presses; the game calls it after every step.
  void endTick() {
    _pressed.clear();
    _mousePressed.clear();
    _padPressed.clear();
    _triggerPressed.clear();
    _scriptPressed.clear();
    _touchPressed.clear();
    _touchDigit = -1;
  }
}
