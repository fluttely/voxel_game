import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import 'map_canvas.dart';
import 'world_map.dart';

/// The minimap in the HUD's corner: [side] pixels of map, the player in its
/// middle, and under it what its colours mean ([legendOf]).
class Minimap extends StatelessWidget {
  /// The minimap of [game], [side] pixels a side.
  const Minimap(this.game, {super.key, required this.side});

  /// The game whose map it is.
  final VoxelGame game;

  /// Pixels a side.
  final double side;

  /// Pixels a side at the most.
  static const double largest = 240.0;

  /// The share of the screen's height it takes at the most.
  static const double heightShare = 0.4;

  /// What the minimap's colours mean, and the press that opens the whole
  /// map on the device the player last used.
  static String legendOf(VoxelGame game) => [
    'North is up',
    'red: monsters',
    'green: animals',
    'blue: pets',
    'cyan: waypoints',
    'brown: mounts',
    'white: spawn',
    'squares: places found',
    if (WorldMap.keyOf(game) case final key?) '$key again: big map',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: side + 6,
          height: side + 6,
          padding: const EdgeInsets.all(3),
          color: Colors.black.withValues(alpha: 0.7),
          child: MapCanvas(game, whole: false),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: side + 6,
          child: HudSelector(
            frames: game.frames,
            select: () => legendOf(game),
            builder: (context, legend) => Text(
              legend,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFCCCCCC),
                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 2)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
