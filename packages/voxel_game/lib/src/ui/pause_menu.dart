import 'package:flutter/material.dart';

import '../core/voxel_game.dart';
import 'game_screen.dart';

/// The game menu (`PauseScreen`): resume, the settings (`SettingsScreen`), a
/// button for each of the game's own screens that has a `ScreenSpec.menu`, and
/// quit when there is somewhere to quit to. The world keeps running behind it; a press of pause resumes too.
class PauseMenu extends StatelessWidget {
  /// The menu of [game]; [onQuit] is its Quit, shown only when given.
  const PauseMenu(this.game, {super.key, this.onQuit});

  /// The game.
  final VoxelGame game;

  /// Called by Quit; no Quit when null.
  final VoidCallback? onQuit;

  @override
  Widget build(BuildContext context) {
    final quit = onQuit;
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Material(
          color: const Color(0xEE1E2430),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Game menu', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: game.closeScreen, child: const Text('Resume')),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => game.openScreen(const SettingsScreen()),
                    child: const Text('Settings'),
                  ),
                  for (final e in game.spec.screens.entries)
                    if (e.value.menu case final label?) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: () => game.openScreen(DeclaredScreen(e.key)), child: Text(label)),
                    ],
                  if (quit != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: quit, child: const Text('Quit')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
