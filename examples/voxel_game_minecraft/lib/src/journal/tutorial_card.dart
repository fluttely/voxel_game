import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import '../ui/hint_card.dart';
import 'tutorial.dart';
import 'tutorial_steps.dart';

/// The tutorial's card while it runs (`Tutorial`): `Step N/10`, the step's
/// title and hint, and a button that skips it all (F6 does the same).
/// Nothing once it has ended.
class TutorialCard extends StatelessWidget {
  /// The card of [game]'s tutorial.
  const TutorialCard(this.game, {super.key});

  /// The game whose tutorial it shows.
  final VoxelGame game;

  /// The card's colour.
  static const Color gold = Color(0xFFF2CC59);

  @override
  Widget build(BuildContext context) {
    final tutorial = Tutorial.of(game);
    return HudSelector(
      frames: game.frames,
      select: () => tutorial.step,
      builder: (context, step) {
        final s = tutorial.current;
        if (s == null) return const SizedBox.shrink();
        return HintCard(
          label: 'Step ${step + 1}/${tutorialSteps.length}',
          title: s.title,
          hint: s.hint,
          accent: gold,
          action: (text: 'Skip tutorial (F6)', onPressed: () => tutorial.skip(game)),
        );
      },
    );
  }
}
