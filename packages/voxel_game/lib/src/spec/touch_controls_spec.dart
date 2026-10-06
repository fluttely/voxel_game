/// The controls a finger plays with: a floating stick in the lower-left zone,
/// jump and sneak at the bottom right, the view and pause at the top right,
/// and the hotbar's own taps (`DefaultHud`). Shown only while the last device
/// was a finger (`InputMap.lastDevice`).
///
/// The world itself is the attack and use button: a finger on it looks, mines
/// or uses (`InputMap`), so there is no button for either.
class TouchControlsSpec {
  /// Controls; the defaults are [standard]'s.
  const TouchControlsSpec({
    this.stickRadius = 60.0,
    this.stickZoneWidth = 0.4,
    this.stickZoneHeight = 0.7,
    this.sprintAt = 0.9,
    this.buttonSize = 64.0,
    this.sneakToggles = true,
    this.dropHold = const Duration(milliseconds: 400),
  }) : assert(stickRadius > 0.0, 'stickRadius must be positive'),
       assert(stickZoneWidth > 0.0 && stickZoneWidth <= 1.0, 'stickZoneWidth is a share of the width, 0 to 1'),
       assert(stickZoneHeight > 0.0 && stickZoneHeight <= 1.0, 'stickZoneHeight is a share of the height, 0 to 1'),
       assert(sprintAt > 0.0 && sprintAt <= 1.0, 'sprintAt is a share of the stick\'s reach, 0 to 1'),
       assert(buttonSize > 0.0, 'buttonSize must be positive');

  /// The kit's layout, for a phone held landscape.
  static const TouchControlsSpec standard = TouchControlsSpec();

  /// How far, in logical pixels, the stick's knob travels from where the thumb
  /// landed; pushed that far it is a full step.
  final double stickRadius;

  /// The share of the safe area's width, from its left edge, where a thumb
  /// that lands grabs the stick, centred where it landed.
  final double stickZoneWidth;

  /// The share of the safe area's height, from its bottom edge, of that zone.
  final double stickZoneHeight;

  /// The share of [stickRadius] past which the stick also holds sprint: a run
  /// needs no button of its own.
  final double sprintAt;

  /// The side of the view and pause buttons and of sneak, in logical pixels;
  /// jump is a quarter bigger.
  final double buttonSize;

  /// Whether sneak is a switch (a tap on, a tap off) rather than held: a thumb
  /// that holds it cannot also look.
  final bool sneakToggles;

  /// How long a finger stays on the hotbar's slot in hand before it drops one
  /// of what the slot holds; positive (asserted where it is read, since a
  /// constant constructor cannot compare durations).
  final Duration dropHold;
}
