import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import 'game_stats.dart';

/// What the player did in this world (`GameStats`), from the game menu: the
/// time played, the metres walked, blocks broken and placed, creatures
/// defeated, deaths, trips through a portal, things made.
class StatsScreen extends StatelessWidget {
  /// The stats of [game]'s world.
  const StatsScreen(this.game, {super.key});

  /// A `ScreenBuilder` of this screen.
  static Widget builder(BuildContext context, VoxelGame game) => StatsScreen(game);

  /// The game whose world it counts.
  final VoxelGame game;

  /// The stats as the screen lists them, a line each.
  static List<String> linesOf(VoxelGame game) {
    final s = GameStats.of(game);
    final p = game.player;
    return [
      'Level ${p.level}',
      'Time played  ${GameStats.timeLabel(s.playTime)}',
      'Walked  ${s.walked.floor()} m',
      'Blocks broken  ${s.blocksBroken}',
      'Blocks placed  ${s.blocksPlaced}',
      'Creatures defeated  ${s.kills}',
      'Deaths  ${s.deaths}',
      'Trips through a portal  ${s.trips}',
      'Things made  ${s.crafted}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Stats', style: TextStyle(fontSize: 20)),
                const SizedBox(height: 12),
                HudSelector(
                  frames: game.frames,
                  select: () => linesOf(game).join('\n'),
                  builder: (context, lines) => Text(lines, style: const TextStyle(fontSize: 15, height: 1.6)),
                ),
                const SizedBox(height: 12),
                FilledButton(autofocus: true, onPressed: game.closeScreen, child: const Text('Back to the game')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
