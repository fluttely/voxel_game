import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import 'tutorial.dart';
import 'tutorial_steps.dart';

/// The tutorial in the game menu (Tutorial, while it runs): the step at hand
/// and a skip of it all, what F6 does, for a pad. It opens on Back to the
/// game, so a stray press does not skip.
class TutorialScreen extends StatelessWidget {
  /// The screen, over [game].
  const TutorialScreen(this.game, {super.key});

  /// A `ScreenBuilder` of this screen.
  static Widget builder(BuildContext context, VoxelGame game) => TutorialScreen(game);

  /// Whether the game menu of [game] lists it: while its tutorial runs
  /// (`ScreenSpec.listed`).
  static bool listed(VoxelGame game) => Tutorial.of(game).current != null;

  /// The game whose tutorial it shows.
  final VoxelGame game;

  @override
  Widget build(BuildContext context) {
    final tutorial = Tutorial.of(game);
    final step = tutorial.current;
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Tutorial', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
                  if (step != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Step ${tutorial.step + 1}/${tutorialSteps.length}: ${step.title}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    // Closed first, so the player sees it told.
                    onPressed: () {
                      game.closeScreen();
                      tutorial.skip(game);
                    },
                    child: const Text('Skip tutorial (F6)'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(autofocus: true, onPressed: game.closeScreen, child: const Text('Back to the game')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
