import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/voxel_game.dart';
import '../input/input_device.dart';
import '../input/voxel_action.dart';
import '../spec/touch_controls_spec.dart';
import 'hud_selector.dart';

/// The controls a finger plays with, laid out by a [TouchControlsSpec] inside
/// the safe area: a floating stick in the lower-left zone, jump and sneak at
/// the bottom right, the view and pause at the top right. The hotbar is the
/// HUD's (`DefaultHud` takes its own taps), and the world is the attack and
/// use button.
///
/// It shows itself only while the last device was a finger
/// (`InputMap.lastDevice`), the game is in `gameplay` and no screen is open,
/// so a keyboard, a pad or a pause takes it off the screen and a touch puts it
/// back. `VoxelGameWidget` mounts it between the world and the HUD when
/// `VoxelGameSpec.touchControls` is set; a game that builds its own view puts
/// it there itself.
///
/// Every control claims the finger that lands on it (`InputMap.claimTouch`),
/// so that finger is never also a look, a dig or a tap on the world, and
/// writes the same actions a key does: nothing downstream can tell them apart.
class TouchControls extends StatelessWidget {
  /// The controls of [game], laid out by [spec].
  const TouchControls(this.game, this.spec, {super.key});

  /// The game played.
  final VoxelGame game;

  /// The layout.
  final TouchControlsSpec spec;

  @override
  Widget build(BuildContext context) => HudSelector(
    frames: game.frames,
    select: () => game.input.lastDevice == InputDevice.touch && game.gameplay && game.openScreen.value == null,
    builder: (context, shown) => shown ? _TouchLayer(game, spec) : const SizedBox.shrink(),
  );
}

// The margin between a control and the safe area's edge, and between two
// controls.
const double _margin = 20.0;

class _TouchLayer extends StatelessWidget {
  const _TouchLayer(this.game, this.spec);

  final VoxelGame game;
  final TouchControlsSpec spec;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final small = spec.buttonSize * 0.75;
    final jump = spec.buttonSize * 1.25;
    return Padding(
      padding: pad,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            children: [
              Positioned(
                left: 0.0,
                bottom: 0.0,
                width: size.width * spec.stickZoneWidth,
                height: size.height * spec.stickZoneHeight,
                child: _MoveStick(game, spec),
              ),
              Positioned(
                right: _margin,
                bottom: _margin,
                child: _HoldButton(game, action: VoxelAction.jump, icon: Icons.arrow_upward, size: jump),
              ),
              Positioned(
                right: _margin + (jump - spec.buttonSize) * 0.5,
                bottom: _margin * 2 + jump,
                child: spec.sneakToggles
                    ? _SwitchButton(game, action: VoxelAction.sneak, icon: Icons.arrow_downward, size: spec.buttonSize)
                    : _HoldButton(game, action: VoxelAction.sneak, icon: Icons.arrow_downward, size: spec.buttonSize),
              ),
              Positioned(
                right: _margin,
                top: _margin,
                child: _PressButton(game, action: VoxelAction.pause, icon: Icons.pause, size: small),
              ),
              Positioned(
                right: _margin * 2 + small,
                top: _margin,
                child: _PressButton(game, action: VoxelAction.toggleView, icon: Icons.cameraswitch, size: small),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Claims every touch that lands on [child], for the control it is: [down]
/// hears the touch land, [lift] hears its pointer lift or be cancelled.
Widget _claiming(
  VoxelGame game,
  Widget child, {
  required void Function(int pointer) down,
  void Function(int pointer)? lift,
}) => Listener(
  behavior: HitTestBehavior.opaque,
  onPointerDown: (e) {
    if (e.kind != PointerDeviceKind.touch) return;
    game.input.claimTouch(e.pointer);
    down(e.pointer);
  },
  onPointerUp: (e) => lift?.call(e.pointer),
  onPointerCancel: (e) => lift?.call(e.pointer),
  child: child,
);

/// The look of every button here: dark glass and a pale rim, lit while it is
/// held or switched on.
class _ButtonFace extends StatelessWidget {
  const _ButtonFace({required this.icon, required this.size, required this.lit});

  final IconData icon;
  final double size;
  final bool lit;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: lit ? const Color.fromRGBO(255, 255, 255, 0.34) : const Color.fromRGBO(0, 0, 0, 0.42),
      shape: BoxShape.circle,
      border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.55), width: 2.0),
    ),
    child: Icon(icon, size: size * 0.5, color: Colors.white),
  );
}

/// Holds its action while a finger is on it (jump: also swims up and climbs).
class _HoldButton extends StatefulWidget {
  const _HoldButton(this.game, {required this.action, required this.icon, required this.size});

  final VoxelGame game;
  final VoxelAction action;
  final IconData icon;
  final double size;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  int? _pointer;

  void _press(int pointer) {
    if (_pointer != null) return;
    widget.game.input.setTouchHeld(widget.action, true);
    setState(() => _pointer = pointer);
  }

  void _lift(int pointer) {
    // A finger keeps the route it landed on: a button taken off the screen
    // under it still hears it lift, after [dispose] has let go.
    if (!mounted || pointer != _pointer) return;
    widget.game.input.setTouchHeld(widget.action, false);
    setState(() => _pointer = null);
  }

  @override
  void dispose() {
    // Taken off the screen under the finger (a screen opened, a key was
    // pressed): the lift will never come here, so let go now.
    if (_pointer != null) widget.game.input.setTouchHeld(widget.action, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _claiming(
    widget.game,
    _ButtonFace(icon: widget.icon, size: widget.size, lit: _pointer != null),
    down: _press,
    lift: _lift,
  );
}

/// Flips its action on and off, a tap each (sneak). The state is the input
/// map's (`InputMap.touchToggle`), so whatever clears the map's held inputs
/// turns it off too, and the button draws what the map holds.
class _SwitchButton extends StatelessWidget {
  const _SwitchButton(this.game, {required this.action, required this.icon, required this.size});

  final VoxelGame game;
  final VoxelAction action;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => _claiming(
    game,
    HudSelector(
      frames: game.frames,
      select: () => game.input.touchHeld(action),
      builder: (context, on) => _ButtonFace(icon: icon, size: size, lit: on),
    ),
    down: (_) => game.input.touchToggle(action),
  );
}

/// Presses its action once as the finger lands (the view, pause).
class _PressButton extends StatelessWidget {
  const _PressButton(this.game, {required this.action, required this.icon, required this.size});

  final VoxelGame game;
  final VoxelAction action;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => _claiming(
    game,
    _ButtonFace(icon: icon, size: size, lit: false),
    down: (_) => game.input.touchPress(action),
  );
}

/// The movement stick: a thumb that lands anywhere in the zone grabs it, the
/// ring centred where it landed, and the knob follows the thumb out to
/// `stickRadius`. Pushed past `sprintAt` of that it also holds sprint. The
/// lift springs it back. A second finger in the zone while one steers is not
/// the stick's: it is left to the world, where it looks.
class _MoveStick extends StatefulWidget {
  const _MoveStick(this.game, this.spec);

  final VoxelGame game;
  final TouchControlsSpec spec;

  @override
  State<_MoveStick> createState() => _MoveStickState();
}

class _MoveStickState extends State<_MoveStick> {
  int? _pointer;
  Offset _origin = Offset.zero;
  Offset _knob = Offset.zero;

  void _grab(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch || _pointer != null) return;
    widget.game.input.claimTouch(e.pointer);
    setState(() {
      _pointer = e.pointer;
      _origin = e.localPosition;
      _knob = Offset.zero;
    });
  }

  // A finger keeps the route it landed on: a stick taken off the screen under
  // the thumb still hears it move and lift, after [dispose] has let go.
  void _drag(PointerMoveEvent e) {
    if (!mounted || e.pointer != _pointer) return;
    final r = widget.spec.stickRadius;
    var v = e.localPosition - _origin;
    if (v.distance > r) v = v * (r / v.distance);
    setState(() => _knob = v);
    final n = v / r;
    // Screen down is +y, and so is walking back (forward is -1 on the stick's
    // y, `TouchAxis.y`), so the offset goes through as it is.
    widget.game.input
      ..touchMove(n.dx, n.dy)
      ..setTouchHeld(VoxelAction.sprint, n.distance > widget.spec.sprintAt);
  }

  void _lift(int pointer) {
    if (!mounted || pointer != _pointer) return;
    setState(() => _pointer = null);
    _letGo();
  }

  void _letGo() => widget.game.input
    ..touchMove(0.0, 0.0)
    ..setTouchHeld(VoxelAction.sprint, false);

  @override
  void dispose() {
    if (_pointer != null) _letGo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.spec.stickRadius;
    final knob = r * 0.8;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _grab,
      onPointerMove: _drag,
      onPointerUp: (e) => _lift(e.pointer),
      onPointerCancel: (e) => _lift(e.pointer),
      child: _pointer == null
          ? const SizedBox.expand()
          : Stack(
              children: [
                Positioned(
                  left: _origin.dx - r,
                  top: _origin.dy - r,
                  child: Container(
                    width: r * 2,
                    height: r * 2,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(0, 0, 0, 0.32),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.45), width: 2.0),
                    ),
                  ),
                ),
                Positioned(
                  left: _origin.dx + _knob.dx - knob * 0.5,
                  top: _origin.dy + _knob.dy - knob * 0.5,
                  child: Container(
                    width: knob,
                    height: knob,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(255, 255, 255, 0.28),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.7), width: 2.0),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
