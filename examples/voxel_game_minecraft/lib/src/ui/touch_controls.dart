import 'package:flutter/material.dart';

import '../game/input.dart';
import 'hud.dart';

/// The controls a phone plays with: the movement stick, the button cluster and
/// the hotbar's own hit boxes, laid out the way Minecraft lays them out — stick
/// on the left, jump and its neighbours on the right, the hotbar along the
/// bottom with the bag at its end, pause in the top corner.
///
/// Two things decide the shape of this file.
///
/// **It is widgets, not [HudPainter].** A `CustomPainter` is paint and nothing
/// else: it is handed a canvas, never a pointer. A control has to be hit-tested,
/// has to own the finger that lands on it for as long as that finger is down,
/// and has to keep that finger away from the world underneath — all three are
/// the widget layer's job.
///
/// **It sits beside the world's `Listener`, not inside it.** A `Stack` hit-tests
/// its children front to back and stops at the first that takes the pointer, so
/// an opaque button here is the end of the road for that touch. Were these
/// widgets children of the world's `Listener`, every jump would also reach
/// [GameInput.onPointerDown] and the world would read it as a tap on whatever
/// the crosshair happened to be pointing at.
///
/// Nothing here talks to `Game` or `Player`: a control writes to [GameInput] and
/// the simulation reads the same [GameInput.down] / [GameInput.justPressed] it
/// reads for a key or a pad button.
class TouchControls extends StatefulWidget {
  const TouchControls({super.key, required this.input});

  final GameInput input;

  /// Every action a button here can be holding. The layer is taken off the
  /// screen the moment a menu opens, and a finger that was holding jump gets no
  /// lift event when that happens — so the layer lets go of all of them on the
  /// way out.
  static const List<GameAction> heldActions = [
    GameAction.jump,
    GameAction.sneak,
    GameAction.sprint,
    GameAction.interact,
    GameAction.inventory,
    GameAction.pause,
  ];

  /// The stick's own middle, far enough up to clear the hotbar row.
  static const double stickRadius = 62.0;
  static const Offset stickInset = Offset(86.0, 150.0);

  /// The right-hand cluster, measured in from the bottom-right corner.
  static const Offset jumpInset = Offset(74.0, 150.0);
  static const Offset sneakInset = Offset(168.0, 132.0);
  static const Offset interactInset = Offset(74.0, 252.0);
  static const double jumpDiameter = 84.0;
  static const double smallDiameter = 64.0;

  @override
  State<TouchControls> createState() => _TouchControlsState();
}

class _TouchControlsState extends State<TouchControls> {
  bool _sneaking = false;

  @override
  void dispose() {
    for (final a in TouchControls.heldActions) {
      widget.input.setTouchHeld(a, false);
    }
    widget.input.touchMove(0.0, 0.0);
    super.dispose();
  }

  /// Sneak latches, the way it does on a phone in Minecraft: a thumb cannot
  /// hold a button and still work the rest of the screen.
  void _toggleSneak() {
    setState(() => _sneaking = !_sneaking);
    widget.input.setTouchHeld(GameAction.sneak, _sneaking);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final bag = Hud.hotbarSlotRect(size, 9);
        return Stack(
          children: [
            Positioned(
              left: 12.0,
              top: 10.0,
              child: _HoldButton(
                input: widget.input,
                action: GameAction.pause,
                icon: Icons.pause,
                diameter: 44.0,
                rounded: true,
              ),
            ),
            Positioned(
              left: TouchControls.stickInset.dx - TouchControls.stickRadius,
              top: size.height - TouchControls.stickInset.dy - TouchControls.stickRadius,
              child: _MoveStick(input: widget.input, radius: TouchControls.stickRadius),
            ),
            _cluster(
              size,
              TouchControls.interactInset,
              TouchControls.smallDiameter,
              _HoldButton(
                input: widget.input,
                action: GameAction.interact,
                icon: Icons.back_hand,
                diameter: TouchControls.smallDiameter,
              ),
            ),
            _cluster(
              size,
              TouchControls.sneakInset,
              TouchControls.smallDiameter,
              _LatchButton(
                icon: Icons.arrow_downward,
                diameter: TouchControls.smallDiameter,
                on: _sneaking,
                onTap: _toggleSneak,
              ),
            ),
            _cluster(
              size,
              TouchControls.jumpInset,
              TouchControls.jumpDiameter,
              _HoldButton(
                input: widget.input,
                action: GameAction.jump,
                icon: Icons.arrow_upward,
                diameter: TouchControls.jumpDiameter,
              ),
            ),
            // The hotbar is painted by the HUD; these are only its hit boxes,
            // grown a little so a thumb can find a 50 px square.
            for (var i = 0; i < 9; i++)
              Positioned.fromRect(
                rect: Hud.hotbarSlotRect(size, i).inflate(2.0),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => widget.input.touchHotbar(i),
                ),
              ),
            Positioned.fromRect(
              rect: bag,
              child: _HoldButton(
                input: widget.input,
                action: GameAction.inventory,
                icon: Icons.backpack,
                diameter: bag.width,
                rounded: true,
              ),
            ),
          ],
        );
      },
    );
  }

  /// One button of the right-hand cluster, placed by its distance from the
  /// bottom-right corner.
  Widget _cluster(Size size, Offset inset, double diameter, Widget child) => Positioned(
        left: size.width - inset.dx - diameter * 0.5,
        top: size.height - inset.dy - diameter * 0.5,
        child: child,
      );
}

/// The look of every button here: dark glass, a pale rim, brighter while it is
/// being pressed.
class _ButtonFace extends StatelessWidget {
  const _ButtonFace({required this.icon, required this.diameter, required this.lit, this.rounded = false});

  final IconData icon;
  final double diameter;
  final bool lit;
  final bool rounded;

  @override
  Widget build(BuildContext context) => Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: lit ? const Color.fromRGBO(255, 255, 255, 0.34) : const Color.fromRGBO(0, 0, 0, 0.42),
          shape: rounded ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: rounded ? BorderRadius.circular(8.0) : null,
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.55), width: 2.0),
        ),
        child: Icon(icon, size: diameter * 0.5, color: Colors.white),
      );
}

/// A button that holds its action for as long as the finger is on it — jump,
/// interact, and the one-shots (inventory, pause) that only ever read the press.
class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.input,
    required this.action,
    required this.icon,
    required this.diameter,
    this.rounded = false,
  });

  final GameInput input;
  final GameAction action;
  final IconData icon;
  final double diameter;
  final bool rounded;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _down = false;

  void _set(bool down) {
    widget.input.setTouchHeld(widget.action, down);
    setState(() => _down = down);
  }

  @override
  void dispose() {
    if (_down) widget.input.setTouchHeld(widget.action, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: _ButtonFace(icon: widget.icon, diameter: widget.diameter, lit: _down, rounded: widget.rounded),
      );
}

/// A button that stays down until it is tapped again; it shows which way it is
/// latched. The action itself is held through the same [GameInput.setTouchHeld]
/// a finger would hold it with, so nothing downstream knows the difference.
class _LatchButton extends StatelessWidget {
  const _LatchButton({required this.icon, required this.diameter, required this.on, required this.onTap});

  final IconData icon;
  final double diameter;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onTap(),
        child: _ButtonFace(icon: icon, diameter: diameter, lit: on),
      );
}

/// The movement stick: a ring with a knob that follows the thumb and springs
/// back when it lifts. Pushed all the way out it sprints, which is how
/// Minecraft sprints on a phone — there is no second button for it.
class _MoveStick extends StatefulWidget {
  const _MoveStick({required this.input, required this.radius});

  final GameInput input;
  final double radius;

  /// A thumb resting on the stick is not a step.
  static const double deadzone = 0.15;

  /// Past this much of the ring, the walk becomes a run.
  static const double sprintAt = 0.92;

  @override
  State<_MoveStick> createState() => _MoveStickState();
}

class _MoveStickState extends State<_MoveStick> {
  Offset _knob = Offset.zero;
  int? _pointer;

  void _grab(PointerDownEvent e) {
    _pointer = e.pointer;
    _push(e.localPosition);
  }

  void _drag(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _push(e.localPosition);
  }

  void _release() {
    _pointer = null;
    setState(() => _knob = Offset.zero);
    widget.input.touchMove(0.0, 0.0);
    widget.input.setTouchHeld(GameAction.sprint, false);
  }

  void _push(Offset local) {
    final centre = Offset(widget.radius, widget.radius);
    var v = local - centre;
    final len = v.distance;
    if (len > widget.radius) v = v * (widget.radius / len);
    setState(() => _knob = v);
    final n = v / widget.radius;
    final reach = n.distance;
    // Screen down is +y and so is walking backwards ([GameInput.moveAxisY]
    // reads forward as -1), so the offset goes through as it is.
    if (reach < _MoveStick.deadzone) {
      widget.input.touchMove(0.0, 0.0);
    } else {
      widget.input.touchMove(n.dx, n.dy);
    }
    widget.input.setTouchHeld(GameAction.sprint, reach > _MoveStick.sprintAt);
  }

  @override
  void dispose() {
    widget.input.touchMove(0.0, 0.0);
    widget.input.setTouchHeld(GameAction.sprint, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.radius * 2;
    const knob = 52.0;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _grab,
      onPointerMove: _drag,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: SizedBox(
        width: d,
        height: d,
        child: Stack(
          children: [
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(0, 0, 0, 0.32),
                shape: BoxShape.circle,
                border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.45), width: 2.0),
              ),
            ),
            Positioned(
              left: widget.radius + _knob.dx - knob * 0.5,
              top: widget.radius + _knob.dy - knob * 0.5,
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
      ),
    );
  }
}
