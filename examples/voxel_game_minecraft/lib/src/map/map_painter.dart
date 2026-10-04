import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import '../structures/structures.dart';
import '../waypoints/waypoints.dart';
import 'map_mark.dart';
import 'world_map.dart';

/// The map drawn: the world as [WorldMap.picture] has it, the places marked
/// on it ([marksOf]), every creature a dot ([dotOf]) and the player an
/// arrow pointing where they face, north up.
///
/// The minimap ([whole] false) is a window [minimapBlocks] across centred on
/// the player; the whole map fits the picture into its box, its marks drawn
/// larger and named.
class MapPainter extends CustomPainter {
  /// The map of [game], repainted on every frame: the whole one when
  /// [whole], else the minimap.
  MapPainter(this.game, {required this.whole}) : super(repaint: game.frames);

  /// The game whose map it is.
  final VoxelGame game;

  /// Whether this is the whole map rather than the minimap.
  final bool whole;

  /// Blocks across the minimap.
  static const double minimapBlocks = 96.0;

  /// Each structure the map marks, by its name in the spec: what it is
  /// called and its square's colour.
  static const Map<String, (String, Color)> structures = {
    'dungeon': ('Dungeon', Color(0xFFD94040)),
    'tower': ('Tower', Color(0xFFBFBFD9)),
    'camp': ('Camp', Color(0xFFF29933)),
    'village': ('Village', Color(0xFFF2E666)),
    'ruins': ('Ruin', Color(0xFF998C73)),
    'well': ('Well', Color(0xFF59A6F2)),
    'mine': ('Mine', Color(0xFF8C6640)),
    'temple': ('Temple', Color(0xFFF2CC80)),
    'fortress': ('Fortress', Color(0xFFB333CC)),
  };

  /// A waypoint's diamond.
  static const Color waypointColour = Color(0xFF4DF2FF);

  /// A tamed mount's dot, its ring and its name.
  static const Color mountColour = Color(0xFF99612E), mountRing = Color(0xFFFFE6B3), mountName = Color(0xFFE6BF80);

  /// The spawn's dot.
  static const Color spawnColour = Colors.white;

  /// A creature that hunts the player, one that does not, and a tamed one.
  static const Color hostileColour = Color(0xFFFF4D4D),
      passiveColour = Color(0xFF66FF66),
      petColour = Color(0xFF6699FF);

  /// Where nothing is drawn.
  static const Color background = Color(0xFF0D0D14);

  /// Whether creatures of [spec] hunt the player unprovoked.
  static bool hostile(MobSpec spec) => spec.brain.any((b) => b is Hunt && !b.whenProvoked);

  /// The dot of [mob]: tamed, hostile or neither.
  static Color dotOf(Mob mob) => mob.tamed ? petColour : (hostile(mob.spec) ? hostileColour : passiveColour);

  /// The places [game]'s map marks in the dimension the player is in: the
  /// spawn (in the main one), the structures found, the waypoints and the
  /// tamed mounts.
  static List<MapMark> marksOf(VoxelGame game) {
    final dimension = game.dimension;
    final spawn = game.player.spawnPoint;
    return [
      if (dimension == VoxelGameSpec.mainDimension) MapMark(MapMarkShape.dot, spawn.x, spawn.z, 'Spawn', spawnColour),
      for (final s in Structures.of(game).foundIn(dimension))
        MapMark(MapMarkShape.square, s.x + 0.5, s.z + 0.5, structures[s.name]!.$1, structures[s.name]!.$2),
      for (final w in Waypoints.of(game).all)
        if (w.dimension == dimension)
          MapMark(MapMarkShape.diamond, w.cell.x + 0.5, w.cell.z + 0.5, w.label, waypointColour),
      for (final m in game.mobs)
        if (m.tamed && m.spec.mount != null && !m.isDead)
          MapMark(MapMarkShape.ring, m.position.x, m.position.z, m.name, mountColour),
    ];
  }

  /// Draws a mark of [shape] in [colour] centred on [at], [scale] times the
  /// minimap's size: also the legend's.
  static void drawMark(Canvas canvas, MapMarkShape shape, Offset at, Color colour, double scale) {
    final fill = Paint()..color = colour;
    final edge = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    switch (shape) {
      case MapMarkShape.dot:
        canvas.drawCircle(at, 3.0 * scale, fill);
        canvas.drawCircle(at, 3.0 * scale, edge);
      case MapMarkShape.square:
        final r = 3.5 * scale;
        final box = Rect.fromCenter(center: at, width: 2 * r, height: 2 * r);
        canvas.drawRect(box, fill);
        canvas.drawRect(box, edge);
      case MapMarkShape.diamond:
        final r = 4.5 * scale;
        canvas.drawPath(
          Path()
            ..moveTo(at.dx, at.dy - r)
            ..lineTo(at.dx + r, at.dy)
            ..lineTo(at.dx, at.dy + r)
            ..lineTo(at.dx - r, at.dy)
            ..close(),
          fill,
        );
      case MapMarkShape.ring:
        canvas.drawCircle(at, 3.0 * scale, fill);
        canvas.drawCircle(at, 3.0 * scale, edge..color = mountRing);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final picture = WorldMap.of(game).picture;
    final image = picture.image;
    final p = game.player.position;
    final _Frame frame;
    if (whole) {
      if (image == null) return;
      final iw = image.width.toDouble(), ih = image.height.toDouble();
      final s = math.min(size.width / iw, size.height / ih);
      frame = _Frame(
        Rect.fromCenter(center: size.center(Offset.zero), width: iw * s, height: ih * s),
        picture.originX + iw * 0.5,
        picture.originZ + ih * 0.5,
        s,
      );
    } else {
      frame = _Frame(Offset.zero & size, p.x, p.z, size.width / minimapBlocks);
    }
    final icon = whole ? 1.6 : 1.0;
    canvas.save();
    canvas.clipRect(frame.view);
    if (image != null) {
      final at = frame.toScreen(picture.originX.toDouble(), picture.originZ.toDouble());
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(at.dx, at.dy, image.width * frame.s, image.height * frame.s),
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    for (final mark in marksOf(game)) {
      if (!frame.inside(mark.x, mark.z)) continue;
      final at = frame.toScreen(mark.x, mark.z);
      drawMark(canvas, mark.shape, at, mark.colour, icon);
      if (whole) {
        final colour = mark.shape == MapMarkShape.ring ? mountName : mark.colour;
        _label(canvas, mark.label, at + Offset(6 * icon, -7), colour);
      }
    }
    for (final m in game.mobs) {
      if (m.isDead || !frame.inside(m.position.x, m.position.z)) continue;
      canvas.drawCircle(frame.toScreen(m.position.x, m.position.z), 2.5 * icon, Paint()..color = dotOf(m));
    }
    final at = frame.toScreen(p.x, p.z);
    final yaw = game.player.yaw;
    final (fx, fz) = (-math.sin(yaw), -math.cos(yaw));
    final len = 9.0 * icon, half = 4.0 * icon;
    canvas.drawPath(
      Path()
        ..moveTo(at.dx + fx * len, at.dy + fz * len)
        ..lineTo(at.dx - fz * half, at.dy + fx * half)
        ..lineTo(at.dx + fz * half, at.dy - fx * half)
        ..close(),
      Paint()..color = Colors.white,
    );
    if (whole) _label(canvas, 'You', at + const Offset(-10, -24), Colors.white);
    canvas.restore();
  }

  static void _label(Canvas canvas, String text, Offset at, Color colour) {
    (TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 12,
          color: colour,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(1, 1))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout()).paint(canvas, at);
  }

  @override
  bool shouldRepaint(MapPainter old) => old.game != game || old.whole != whole;
}

// Where the map lands in the box: the world point ([cx], [cz]) at [view]'s centre, [s] pixels a block.
class _Frame {
  const _Frame(this.view, this.cx, this.cz, this.s);

  final Rect view;
  final double cx, cz, s;

  Offset toScreen(double x, double z) => Offset(view.center.dx + (x - cx) * s, view.center.dy + (z - cz) * s);

  bool inside(double x, double z) => view.contains(toScreen(x, z));
}
