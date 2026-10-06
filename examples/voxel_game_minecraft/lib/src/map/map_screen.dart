import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import 'map_canvas.dart';
import 'map_mark.dart';
import 'map_painter.dart';
import 'world_map.dart';

/// The whole map (the map action pressed over the minimap, and Map in the
/// game menu): every chunk loaded or explored near the player, its places
/// named, and what the colours mean under it. The world keeps going behind
/// it, so the creatures move on it while it is open.
class MapScreen extends StatelessWidget {
  /// The whole map of [game].
  const MapScreen(this.game, {super.key});

  /// A `ScreenBuilder` of this screen.
  static Widget builder(BuildContext context, VoxelGame game) => MapScreen(game);

  /// The game whose map it is.
  final VoxelGame game;

  /// The line under the title: how much is explored, what grey means, and
  /// the press that closes it on the device the player last used.
  static String subtitleOf(VoxelGame game) => [
    if (WorldMap.keyOf(game) case final key?) '$key: close',
    '${WorldMap.of(game).exploredIn(game.dimension).length} chunks explored',
    'grey: explored, too far to see now',
  ].join(' · ');

  /// What each mark and dot means, in the legend's order.
  static final List<(MapMarkShape, Color, String)> legend = [
    (MapMarkShape.dot, MapPainter.spawnColour, 'spawn'),
    (MapMarkShape.diamond, MapPainter.waypointColour, 'waypoint'),
    (MapMarkShape.ring, MapPainter.mountColour, 'mount'),
    (MapMarkShape.dot, MapPainter.hostileColour, 'monster'),
    (MapMarkShape.dot, MapPainter.passiveColour, 'animal'),
    (MapMarkShape.dot, MapPainter.petColour, 'pet'),
    for (final (name, colour) in MapPainter.structures.values) (MapMarkShape.square, colour, name.toLowerCase()),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 760),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('World map', style: TextStyle(fontSize: 22)),
                  HudSelector(
                    frames: game.frames,
                    select: () => subtitleOf(game),
                    builder: (context, line) => Text(line, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: ClipRect(child: MapCanvas(game, whole: true))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final (shape, colour, name) in legend)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomPaint(size: const Size.square(14), painter: _LegendMark(shape, colour)),
                            const SizedBox(width: 4),
                            Text(name, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
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

// A mark of the legend, drawn as the map draws it.
class _LegendMark extends CustomPainter {
  const _LegendMark(this.shape, this.colour);

  final MapMarkShape shape;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) => MapPainter.drawMark(canvas, shape, size.center(Offset.zero), colour, 1.2);

  @override
  bool shouldRepaint(_LegendMark old) => old.shape != shape || old.colour != colour;
}
