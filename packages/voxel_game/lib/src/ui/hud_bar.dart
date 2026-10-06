import 'dart:ui' show Color;

import '../core/voxel_game.dart';

/// A bar of a game's own in the kit's HUD (`DefaultHud.bars`): stamina, mana,
/// a charge. It sits in the column over the hotbar, under the hearts and over
/// the experience, [label] at its left.
///
/// ```dart
/// hud: (context, game) => DefaultHud(game, bars: [
///   HudBar('Stamina', color: Colors.lightBlueAccent, fill: (game) => game.system<Stamina>().left),
/// ]),
/// ```
class HudBar {
  /// A bar called [label], [color] up to [fill].
  const HudBar(this.label, {required this.fill, required this.color});

  /// What it is called, shown at its left.
  final String label;

  /// How full it is now, 0..1: read every frame, the bar redrawn when it
  /// moves by a hundredth. A value outside 0..1 throws.
  final double Function(VoxelGame game) fill;

  /// What fills it.
  final Color color;
}
