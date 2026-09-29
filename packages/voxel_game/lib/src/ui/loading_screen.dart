import 'package:flutter/material.dart';

import '../core/voxel_game.dart';
import 'hud_selector.dart';
import 'loading_stage.dart';

/// Builds what shows while a `VoxelGameWidget` loads: called when the [stage]
/// changes, never with [LoadingStage.playing]. [game] is null while
/// [LoadingStage.starting]; after it, a piece that shows its progress watches
/// it through a [HudSelector] on [VoxelGame.frames].
typedef LoadingBuilder = Widget Function(BuildContext context, LoadingStage stage, VoxelGame? game);

/// The kit's loading screen: what the widget waits for and, while the window
/// fills, how many of its chunks have a mesh. Pass your own [LoadingBuilder]
/// to replace it.
class LoadingScreen extends StatelessWidget {
  /// The screen of [stage], for [game] (null while it starts).
  const LoadingScreen(this.stage, this.game, {super.key})
    : assert(stage != LoadingStage.playing, 'the game is shown, not loading'),
      assert((game == null) == (stage == LoadingStage.starting), 'a game exists once it has started');

  /// A [LoadingBuilder] of this screen.
  static Widget builder(BuildContext context, LoadingStage stage, VoxelGame? game) => LoadingScreen(stage, game);

  /// The stage shown.
  final LoadingStage stage;

  /// The game being loaded; null while it starts.
  final VoxelGame? game;

  static String _label(LoadingStage stage) => switch (stage) {
    LoadingStage.starting => 'Starting...',
    LoadingStage.filling => 'Generating the world...',
    LoadingStage.warming => 'Preparing the renderer...',
    LoadingStage.playing => throw ArgumentError.value(stage, 'stage', 'the game is shown, not loading'),
  };

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0E1420),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_label(stage)),
            const SizedBox(height: 12),
            SizedBox(
              width: 240,
              child: stage == LoadingStage.filling
                  ? HudSelector(
                      frames: game!.frames,
                      select: () => _filled(game!),
                      builder: (context, value) => LinearProgressIndicator(value: value),
                    )
                  : const LinearProgressIndicator(),
            ),
          ],
        ),
      ),
    );
  }

  /// The share of the window's chunks with a mesh, 0..1.
  static double _filled(VoxelGame game) {
    final side = 2 * game.world.loadRadius + 1;
    return (game.world.meshCount / (side * side)).clamp(0.0, 1.0);
  }
}
