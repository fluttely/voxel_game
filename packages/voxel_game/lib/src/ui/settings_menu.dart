import 'package:flutter/material.dart';

import '../core/voxel_game.dart';
import '../settings/game_settings.dart';
import 'game_screen.dart';
import 'settings_panel.dart';

/// The settings screen (`SettingsScreen`): the [SettingsPanel] of [game]'s
/// settings, each change put in force at once (`VoxelGame.applySettings`),
/// and Done back to the game menu. It opens on the first row. The world keeps running behind it, so a
/// change shows as it is made.
class SettingsMenu extends StatelessWidget {
  /// The settings of [game].
  const SettingsMenu(this.game, {super.key});

  /// The game.
  final VoxelGame game;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black38,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: const Color(0xEE1E2430),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Settings', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
                    const SizedBox(height: 8),
                    // A phone held sideways is short: the rows scroll, the title and Done stay.
                    Flexible(
                      child: SingleChildScrollView(
                        child: ValueListenableBuilder<GameSettings>(
                          valueListenable: game.settings,
                          builder: (context, value, _) => SettingsPanel(
                            spec: game.spec,
                            value: value,
                            onChanged: game.applySettings,
                            autofocus: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: () => game.openScreen(const PauseScreen()), child: const Text('Done')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
