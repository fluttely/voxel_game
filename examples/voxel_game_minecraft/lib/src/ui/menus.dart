import 'dart:io';

import 'package:flutter/material.dart';

import '../game/game.dart';
import '../game/game_state.dart';
import '../game/net.dart';
import '../game/settings.dart';
import '../game/tutorial.dart';
import 'settings_panel.dart';

/// Escape: the settings (stage 24, rows built by `SettingsPanel`, kept in
/// settings.cfg), the stats block (stage 30), resume, save, save & back to
/// title (solo), save & quit. The world keeps running behind it; only the
/// mouse is released.
class PauseMenu extends StatefulWidget {
  const PauseMenu({super.key, required this.game});
  final Game game;

  @override
  State<PauseMenu> createState() => _PauseMenuState();
}

class _PauseMenuState extends State<PauseMenu> {
  Game get game => widget.game;
  Settings get settings => Settings.instance;
  bool _stats = false;

  Widget _button(String text, VoidCallback cb) => SettingsPanel.button(text, cb);

  @override
  Widget build(BuildContext context) {
    // The overlay sits in the game's Stack with no Scaffold above it: sliders
    // and switches need a Material ancestor (and text its default style), or
    // they paint the red "No Material widget found" error instead.
    return Material(
      type: MaterialType.transparency,
      child: Container(
      color: const Color.fromRGBO(0, 0, 0, 0.6),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Menu', style: TextStyle(fontSize: 36, color: Colors.white)),
              const SizedBox(height: 6),
              Text(
                'WASD move · Space jump${Settings.instance.climbWalls ? ' / climb walls' : ''} · Shift sprint · Ctrl sneak\nLMB mine / attack · RMB place / use · E inventory + craft\n1-9 hotbar · Q drop · H eat · V camera · G glide · R ability · M map · J journal · F1 debug${game.playground != null ? '\nPlayground: F5 fly · F7 weather · F8 time of day · F9 rebuild the exhibit you stand in' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 6),
              SettingsPanel(game: game),
              // Stage 30: the stats block, folded under one button.
              _button('Stats', () => setState(() => _stats = !_stats)),
              if (_stats)
                Text(SettingsPanel.statsText(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.white)),
              _button('Resume', () {
                settings.save();
                game.closeScreen();
              }),
              _button('Save', () {
                settings.save();
                game.saveGame();
                game.notify('Game saved');
                game.closeScreen();
              }),
              if (Net.instance.mode == NetMode.solo && game.exitToTitle != null)
                // Stage 30: back to the title; a networked session keeps its peer and quits instead.
                _button('Save & back to title', () async {
                  settings.save();
                  await game.saveGame();
                  Tutorial.instance.stop();
                  game.exitToTitle!();
                }),
              _button('Save & Quit', () async {
                settings.save();
                await game.saveGame();
                exit(0);
              }),
              _button('Quit without saving', () => exit(0)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class DeathScreen extends StatefulWidget {
  const DeathScreen({super.key, required this.game});
  final Game game;

  @override
  State<DeathScreen> createState() => _DeathScreenState();
}

class _DeathScreenState extends State<DeathScreen> {
  @override
  void initState() {
    super.initState();
    GameState.instance.deaths += 1;
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Material(
      type: MaterialType.transparency,
      child: Container(
      color: const Color.fromRGBO(102, 0, 0, 0.6),
      alignment: Alignment.center,
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('You died', style: TextStyle(fontSize: 42, color: Colors.white)),
            Text('Level ${game.player.level} · ${GameState.instance.mobsKilled} kills', style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  game.player.respawn();
                  game.closeScreen();
                },
                child: const Text('Respawn'),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
