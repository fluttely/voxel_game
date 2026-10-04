import 'package:flutter/widgets.dart';
import 'package:voxel_game/voxel_game.dart';

import 'map_painter.dart';
import 'world_map.dart';

/// The map in a box, the whole one or the minimap ([whole]), drawn by a
/// [MapPainter]; while it is shown, every frame of [game] keeps
/// [WorldMap.picture] fresh.
class MapCanvas extends StatefulWidget {
  /// The map of [game]: the whole one when [whole], else the minimap.
  const MapCanvas(this.game, {super.key, required this.whole});

  /// The game whose map it is.
  final VoxelGame game;

  /// Whether this is the whole map rather than the minimap.
  final bool whole;

  @override
  State<MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<MapCanvas> {
  @override
  void initState() {
    super.initState();
    widget.game.frames.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.game.frames.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => WorldMap.of(widget.game).picture.update(widget.game);

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: MapPainter(widget.game, whole: widget.whole),
    size: Size.infinite,
  );
}
