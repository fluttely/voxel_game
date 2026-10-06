import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import '../ui/hint_card.dart';
import 'playground.dart';

/// The card of the playground's exhibit the player walked into
/// (`Playground.current`): its title and what to try there, in blue, for
/// `Playground.cardSeconds`. Nothing outside a playground or an exhibit, and
/// nothing a finger can press.
class ZoneCard extends StatelessWidget {
  /// The card of [game]'s playground.
  const ZoneCard(this.game, {super.key});

  /// The game whose playground it shows.
  final VoxelGame game;

  /// The card's colour.
  static const Color blue = Color(0xFF73BFFF);

  @override
  Widget build(BuildContext context) {
    final playground = Playground.of(game);
    return IgnorePointer(
      child: HudSelector(
        frames: game.frames,
        select: () => playground.cardVisible ? playground.current : null,
        builder: (context, zone) => zone == null
            ? const SizedBox.shrink()
            : HintCard(label: 'Playground', title: zone.title, hint: zone.hint, accent: blue),
      ),
    );
  }
}
