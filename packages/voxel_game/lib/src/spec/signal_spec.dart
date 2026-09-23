/// A game's circuits, by block name: what carries power, what makes it, what
/// answers it. Every state is its own block (a lever off and on, a lamp lit
/// and dark), so a flip is a plain block edit that saves and meshes like any
/// other.
///
/// ```dart
/// signals: SignalSpec(
///   wire: ('wire', 'wire_lit'),
///   levers: {'lever': 'lever_on'},
///   lamps: {'lamp': 'lamp_lit'},
///   explosives: {'tnt': 4.0},
/// ),
/// ```
class SignalSpec {
  /// Circuits.
  const SignalSpec({
    required this.wire,
    this.levers = const {},
    this.buttons = const {},
    this.plates = const {},
    this.sources = const {},
    this.lamps = const {},
    this.doors = const {},
    this.explosives = const {},
  });

  /// The wire, unpowered and powered.
  final (String off, String on) wire;

  /// Levers: off to on. Using one flips it; on, it powers.
  final Map<String, String> levers;

  /// Buttons: up to pressed, and for how many seconds. Using one presses it.
  final Map<String, (String pressed, double seconds)> buttons;

  /// Blocks that power while a body (the player, a mob) stands on them.
  final Set<String> plates;

  /// Blocks that always power (a block of redstone).
  final Set<String> sources;

  /// Lamps: dark to lit while powered.
  final Map<String, String> lamps;

  /// Two-high doors: closed to open while powered.
  final Map<String, String> doors;

  /// Blocks that blow up when powered, and how far the blast reaches.
  final Map<String, double> explosives;
}
