import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import 'playground.dart';

/// The playground's buttons (Playground in the game menu of a playground):
/// the next weather, the next time of day, and a rebuild of the exhibit the
/// player stands in, what F7, F8 and F9 do, for a pad and a phone.
class PlaygroundScreen extends StatelessWidget {
  /// The buttons, over [game].
  const PlaygroundScreen(this.game, {super.key});

  /// A `ScreenBuilder` of this screen.
  static Widget builder(BuildContext context, VoxelGame game) => PlaygroundScreen(game);

  /// Whether the game menu of [game] lists it: in a playground only
  /// (`ScreenSpec.listed`).
  static bool listed(VoxelGame game) => Playground.isOn(game);

  /// The game it acts on.
  final VoxelGame game;

  @override
  Widget build(BuildContext context) {
    final playground = Playground.of(game);
    // Each closes the screen first, so the player sees what it did.
    void then(void Function(VoxelGame game) act) {
      game.closeScreen();
      act(game);
    }

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
                  const Text('Playground', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    autofocus: true,
                    onPressed: () => then(playground.cycleWeather),
                    child: const Text('Next weather (F7)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => then(playground.cycleTime),
                    child: const Text('Next time of day (F8)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => then(playground.rebuildHere),
                    child: const Text('Rebuild this exhibit (F9)'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: game.closeScreen, child: const Text('Back to the game')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
