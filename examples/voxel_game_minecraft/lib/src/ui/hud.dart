import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../core/blocks.dart';
import '../core/items.dart';
import 'package:voxel_engine/core.dart';
import '../game/effects.dart';
import '../game/game.dart';
import '../game/settings.dart';
import '../world/voxel_world.dart';
import 'hud_state.dart';
import 'item_icon.dart';

/// Bars, hotbar, crosshair, notifications, the map, boss bar and everything
/// projected from the world (mob bars, damage numbers, puppet labels).
class Hud {
  Hud._();

  static Color rarityColor(int bonus) {
    if (bonus >= 5) return const Color.fromRGBO(204, 115, 255, 1);
    if (bonus >= 3) return const Color.fromRGBO(102, 166, 255, 1);
    if (bonus >= 1) return const Color.fromRGBO(115, 242, 115, 1);
    return Colors.white;
  }

  static String itemLabel(String id, int bonus) {
    if (bonus <= 0) return Items.displayName(id);
    final tier = bonus >= 5 ? 'Epic' : (bonus >= 3 ? 'Rare' : 'Fine');
    return '$tier ${Items.displayName(id)} +$bonus';
  }

  static Color _c(double r, double g, double b, [double a = 1.0]) =>
      Color.fromRGBO((r * 255).round().clamp(0, 255), (g * 255).round().clamp(0, 255), (b * 255).round().clamp(0, 255), a);

  static Color itemColor(String id) {
    final d = Items.def(id);
    return _c(d.r, d.g, d.b);
  }

  static Color blockColor(int b) {
    final d = Blocks.def(b);
    return _c(d.r, d.g, d.b);
  }

  /// The hotbar's nine slots, bottom centre. The painter draws them and the
  /// on-screen controls tap them, so the geometry lives here and cannot drift
  /// apart; [TouchControls] asks for slot 9 as well, the empty square past the
  /// last one where the bag button goes.
  static const double hotbarSlot = 54.0;

  static Rect hotbarSlotRect(Size size, int i) => Rect.fromLTWH(
      size.width * 0.5 - hotbarSlot * 4.5 + i * hotbarSlot, size.height - 70.0, hotbarSlot - 4, hotbarSlot - 4);

  /// Shared with the inventory, trade and station screens: the item's own
  /// voxel model, the one the hand holds (see [ItemIcon]).
  static void drawItemIcon(Canvas ci, Rect r, String id) => ItemIcon.draw(ci, r, id);

  /// Stage 26: the maps tint a biome's ground so a swamp reads murky and a
  /// jungle deep green (biome id -> tint); every other biome keeps its block
  /// colours.
  static const Map<int, (double, double, double)> biomeTint = {7: (0.30, 0.34, 0.18), 8: (0.10, 0.42, 0.12), 9: (0.45, 0.08, 0.08)}; // 9: the underworld (stage 29)
  static const double biomeTintWeight = 0.45;

  /// One map pixel of a LOADED column: the top block shaded by height, a liquid
  /// over it wins, and the biome tint on top. The biome is sampled once per 4x4
  /// cell ([cache], keyed by the cell, cleared per rebuild): the generator's
  /// noise is too slow per pixel.
  static (double, double, double) mapPixel(VoxelWorld world, int wx, int wz, Map<int, int> cache) {
    final y = world.groundHeight(wx, wz) - 1;
    final id = world.getBlockXYZ(wx, y, wz);
    var r = 0.05, g = 0.05, b = 0.08;
    if (id != Blocks.air) {
      final d = Blocks.def(id);
      final shade = (0.55 + (y - 40) / 80.0).clamp(0.4, 1.2);
      r = d.r * shade;
      g = d.g * shade;
      b = d.b * shade;
    }
    final above = world.getBlockXYZ(wx, y + 1, wz);
    if (above != Blocks.air && Blocks.isLiquid(above)) {
      final d = Blocks.def(above);
      r = d.r;
      g = d.g;
      b = d.b;
    }
    final cx = wx >> 2, cz = wz >> 2;
    final key = (cx & 0xFFFFFF) | ((cz & 0xFFFFFF) << 24);
    final biome = cache[key] ??= world.biomeAt(cx << 2, cz << 2);
    final tint = biomeTint[biome];
    if (tint != null) {
      r += (tint.$1 - r) * biomeTintWeight;
      g += (tint.$2 - g) * biomeTintWeight;
      b += (tint.$3 - b) * biomeTintWeight;
    }
    return (r, g, b);
  }

  static void text(Canvas canvas, String s, Offset at, {double size = 14, Color color = Colors.white, TextAlign align = TextAlign.left, double? width, FontWeight weight = FontWeight.normal, bool shadow = true}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, shadows: shadow ? const [Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(1, 1))] : null)),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: width ?? 1000);
    var x = at.dx;
    if (width != null && align == TextAlign.center) x = at.dx;
    if (width != null && align == TextAlign.right) x = at.dx;
    tp.paint(canvas, Offset(x, at.dy - tp.height + size * 0.2));
  }
}

/// A scrolling body for a hand-painted panel. The painter wraps the rows in
/// [begin] / [end]: the content is clipped to the box and shifted up by
/// [offset], and a bar appears on the right as soon as the rows are taller than
/// the box. A click comes back through [toContent], so the rects the painter
/// recorded are read in the space they were drawn in. Every panel whose list can
/// outgrow its box holds one (the journal keeps one per tab) and feeds it
/// through [PanelScrollInput], so a mouse wheel, a trackpad and a finger all
/// roll it.
class PanelScroll {
  /// How far the content is shifted up, in the panel's own units.
  double offset = 0.0;
  double _max = 0.0;

  /// One wheel notch.
  static const double step = 40.0;

  /// Rolls the wheel: [dy] > 0 walks down the list.
  void wheel(double dy) => offset = (offset + (dy > 0 ? step : -step)).clamp(0.0, _max);

  /// Drags the content by [dy] panel units, the way a finger or a trackpad
  /// swipe moves it: [dy] > 0 pulls the content down, back up the list.
  void drag(double dy) => offset = (offset - dy).clamp(0.0, _max);

  /// Whether there is more below than the box shows.
  bool get hasMore => offset < _max;

  /// A point in panel space read in the content's own space.
  Offset toContent(Offset p) => Offset(p.dx, p.dy + offset);

  /// Clips to [body] and shifts the content up. [contentHeight] is how tall the
  /// rows are all together; anything past [body] becomes scroll.
  void begin(Canvas canvas, Rect body, double contentHeight) {
    _max = math.max(0.0, contentHeight - body.height);
    offset = offset.clamp(0.0, _max);
    canvas.save();
    canvas.clipRect(body);
    canvas.translate(0, -offset);
  }

  /// Ends the clip and draws the bar when there is anything to scroll.
  void end(Canvas canvas, Rect body) {
    canvas.restore();
    if (_max <= 0.0) return;
    final track = body.height;
    final thumb = math.max(30.0, track * track / (track + _max));
    final x = body.right - 5;
    canvas.drawRect(Rect.fromLTWH(x, body.top, 4, track), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.35));
    canvas.drawRect(Rect.fromLTWH(x, body.top + (offset / _max) * (track - thumb), 4, thumb),
        Paint()..color = const Color.fromRGBO(170, 170, 185, 1));
  }
}

/// The pointer events that roll a [PanelScroll], for a panel's [Listener].
/// A mouse wheel arrives as a scroll signal; a trackpad's two-finger swipe
/// (macOS, and Windows precision pads) as a pan-zoom gesture, never a signal;
/// a finger as a plain drag. A finger that moved further than [slop] was
/// scrolling, so its lift is not a tap.
class PanelScrollInput {
  /// [scroll] answers which list a gesture rolls; [scale] how many screen
  /// pixels one panel unit is (a painter that scales its layout sets it).
  PanelScrollInput(this.scroll, this.scale);

  final PanelScroll Function() scroll;
  final double Function() scale;

  /// How far a finger travels before it counts as scrolling, in screen pixels.
  static const double slop = 8.0;

  double _travel = 0.0;

  /// Whether the finger now down has scrolled rather than tapped.
  bool get dragged => _travel > slop;

  void signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) scroll().wheel(e.scrollDelta.dy);
  }

  void panZoom(PointerPanZoomUpdateEvent e) => scroll().drag(e.panDelta.dy / scale());

  void down(PointerDownEvent e) => _travel = 0.0;

  /// A finger drag rolls the list; a mouse drag does not (it carries a stack).
  void move(PointerMoveEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _travel += e.delta.distance;
    if (dragged) scroll().drag(e.delta.dy / scale());
  }
}

/// Where the map lands on the canvas: [view] is the window it is clipped to,
/// the world point ([cx], [cz]) sits at the window's centre and one block is
/// [s] pixels. The corner and the full panel are two frames of the same map.
class MapFrame {
  const MapFrame(this.view, this.cx, this.cz, this.s);
  final Rect view;
  final double cx, cz, s;

  Offset toScreen(double x, double z) => Offset(view.center.dx + (x - cx) * s, view.center.dy + (z - cz) * s);

  bool inside(double x, double z) => view.contains(toScreen(x, z));

  /// The bitmap's rectangle, from the world block at its top-left.
  Rect imageRect(int originX, int originZ, int width, int height) {
    final at = toScreen(originX.toDouble(), originZ.toDouble());
    return Rect.fromLTWH(at.dx, at.dy, width * s, height * s);
  }
}

/// The one map. One pixel per block over every loaded chunk plus every
/// visited one (flat grey when out of the window), kept fresh a few chunks a
/// frame while either frame shows it and composed once a second. The bitmap
/// is fixed to the world, so the ground and everything on it move together
/// under the player's arrow.
class WorldMap {
  static const int maxChunks = 64; // the image never grows past 64x64 chunks (1024 px)
  static const Map<int, String> structureNames = {
    1: 'Dungeon', 2: 'Tower', 3: 'Camp', 4: 'Village', 5: 'Ruin', 6: 'Well', 7: 'Mine', 8: 'Temple', 9: 'Fortress',
  };
  static final Map<int, Color> structureColors = {
    1: Hud._c(0.85, 0.25, 0.25), 2: Hud._c(0.75, 0.75, 0.85), 3: Hud._c(0.95, 0.6, 0.2), 4: Hud._c(0.95, 0.9, 0.4),
    5: Hud._c(0.6, 0.55, 0.45), 6: Hud._c(0.35, 0.65, 0.95), 7: Hud._c(0.55, 0.4, 0.25), 8: Hud._c(0.95, 0.8, 0.5),
    9: Hud._c(0.7, 0.2, 0.8), // stage 29: the fortress
  };
  static final Color waypointColor = Hud._c(0.3, 0.95, 1.0);
  static final Color mountColor = Hud._c(0.6, 0.38, 0.18);
  static const Color spawnColor = Colors.white;

  static const int tile = VoxelWorld.sizeX; // a chunk's side, in pixels
  static const double sliceMs = 2.0; // what refreshing tiles may take a frame
  static const double composeSeconds = 1.0;
  static const double lapRestSeconds = 1.0; // idle between two laps over the tiles

  ui.Image? image;

  /// The world block at the image's top-left.
  int originX = 0, originZ = 0;

  /// One RGBA tile per chunk, refreshed a few a frame in turn, so a map that
  /// is always on never stalls a frame rebuilding itself whole.
  final Map<ChunkPos, Uint8List> _tiles = {};
  final Map<int, int> _biomes = {};
  List<ChunkPos> _queue = const [];
  int _next = 0;
  double _timer = 0.0;
  bool _busy = false;
  bool _shown = false;
  double _sliceMs = 0.0, _sliceSum = 0.0, _composeMs = 0.0;
  int _slices = 0;
  double _rest = 0.0;

  /// The bitmap's size and what keeping it fresh costs.
  String get stats => '${image?.width ?? 0}x${image?.height ?? 0} px, ${_tiles.length} tiles, '
      'tiles ${(_sliceSum / math.max(_slices, 1)).toStringAsFixed(2)} ms a frame on average (worst ${_sliceMs.toStringAsFixed(1)}), '
      'composed in ${_composeMs.toStringAsFixed(1)} ms';

  void update(double dt, Game game) {
    if (game.mapView == MapView.off) {
      _shown = false;
      return;
    }
    if (!_shown) {
      // Opened: a fresh lap, whatever is missing painted at once, then drawn.
      _shown = true;
      _next = _queue.length;
      _refresh(game, sliceMs, fillMissing: true);
      _timer = 0.0;
    } else {
      _rest -= dt;
      if (_rest <= 0.0 || _next < _queue.length) {
        _refresh(game, sliceMs);
      } else {
        _slices += 1; // an idle frame counts toward the average too
      }
    }
    _timer -= dt;
    if (_timer > 0.0 || _busy) return;
    _timer = composeSeconds;
    _compose(game);
  }

  /// The chunks the map covers: every loaded and every visited one within
  /// [maxChunks] / 2 of the player.
  Set<ChunkPos> _inReach(Game game) {
    final here = VoxelWorld.chunkOf(IVec3.floor(game.player.position));
    bool near(ChunkPos c) => (c.x - here.x).abs() <= maxChunks ~/ 2 && (c.z - here.z).abs() <= maxChunks ~/ 2;
    return {...game.visitedChunks.where(near), ...game.world.chunks.keys.where(near)};
  }

  /// Refreshes tiles for up to [budgetMs]: the missing ones first, then the
  /// rest in turn, so a block edited or a chunk loaded shows within a lap.
  /// [fillMissing] paints every missing tile whatever the budget.
  void _refresh(Game game, double budgetMs, {bool fillMissing = false}) {
    final clock = Stopwatch()..start();
    if (_next >= _queue.length) {
      final reach = _inReach(game);
      _tiles.removeWhere((c, _) => !reach.contains(c));
      _queue = [...reach.where((c) => !_tiles.containsKey(c)), ...reach.where(_tiles.containsKey)];
      _next = 0;
      // A biome is sampled per 4x4 cell and never changes: kept across laps,
      // dropped only when the player has wandered far enough to fill it.
      if (_biomes.length > 4 * reach.length * 16) _biomes.clear();
    }
    while (_next < _queue.length &&
        (clock.elapsedMicroseconds < budgetMs * 1000.0 || (fillMissing && !_tiles.containsKey(_queue[_next])))) {
      final c = _queue[_next++];
      _tiles[c] = _paintTile(game.world, c, _tiles[c] ?? Uint8List(tile * tile * 4));
    }
    if (_next >= _queue.length) _rest = lapRestSeconds;
    if (fillMissing) return;
    final ms = clock.elapsedMicroseconds / 1000.0;
    _sliceMs = math.max(_sliceMs, ms);
    _sliceSum += ms;
    _slices += 1;
  }

  Uint8List _paintTile(VoxelWorld world, ChunkPos c, Uint8List px) {
    final loaded = world.chunks.containsKey(c);
    for (var iz = 0; iz < tile; iz++) {
      for (var ix = 0; ix < tile; ix++) {
        var r = 0.22, g = 0.22, b = 0.26; // visited, out of the window
        if (loaded) (r, g, b) = Hud.mapPixel(world, c.x * tile + ix, c.z * tile + iz, _biomes);
        final o = (iz * tile + ix) * 4;
        px[o] = (r * 255).round().clamp(0, 255);
        px[o + 1] = (g * 255).round().clamp(0, 255);
        px[o + 2] = (b * 255).round().clamp(0, 255);
        px[o + 3] = 255;
      }
    }
    return px;
  }

  /// Copies the tiles into one bitmap (transparent where nothing was seen).
  void _compose(Game game) {
    if (_tiles.isEmpty) return;
    final clock = Stopwatch()..start();
    var loX = 1 << 30, loZ = 1 << 30, hiX = -(1 << 30), hiZ = -(1 << 30);
    for (final c in _tiles.keys) {
      loX = math.min(loX, c.x);
      loZ = math.min(loZ, c.z);
      hiX = math.max(hiX, c.x);
      hiZ = math.max(hiZ, c.z);
    }
    final w = (hiX - loX + 1) * tile;
    final h = (hiZ - loZ + 1) * tile;
    final pixels = Uint8List(w * h * 4);
    for (final e in _tiles.entries) {
      final x0 = (e.key.x - loX) * tile;
      final z0 = (e.key.z - loZ) * tile;
      for (var iz = 0; iz < tile; iz++) {
        final at = ((z0 + iz) * w + x0) * 4;
        pixels.setRange(at, at + tile * 4, e.value, iz * tile * 4);
      }
    }
    _composeMs = clock.elapsedMicroseconds / 1000.0;
    final ox = loX * tile, oz = loZ * tile;
    _busy = true;
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, (img) {
      image?.dispose();
      image = img;
      originX = ox;
      originZ = oz;
      _busy = false;
    });
  }
}

class HudPainter extends CustomPainter {
  HudPainter(this.game, this.worldMap, {required Listenable repaint}) : super(repaint: repaint);

  final Game game;
  final WorldMap worldMap;

  static Paint _p(Color c) => Paint()..color = c;

  /// Stage 24: every marker, through [toScreen] (world x, z -> canvas) and
  /// [inside]; [scale] sizes the icons and [labels] names them (the world map
  /// only).
  void _drawMarkers(Canvas canvas, Offset Function(double x, double z) toScreen, bool Function(double x, double z) inside,
      double scale, bool labels) {
    final ring = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final sp = game.player.spawnPoint;
    if (inside(sp.x, sp.z)) {
      final at = toScreen(sp.x, sp.z);
      canvas.drawCircle(at, 3.0 * scale, _p(WorldMap.spawnColor));
      canvas.drawCircle(at, 3.0 * scale, ring);
      if (labels) Hud.text(canvas, 'Spawn', at + const Offset(-46, 4), size: 12, color: WorldMap.spawnColor);
    }
    for (final e in game.discoveredStructures.entries) {
      final x = e.key.x.toDouble(), z = e.key.z.toDouble();
      if (!inside(x, z)) continue;
      final at = toScreen(x, z);
      final r = 3.5 * scale;
      final col = WorldMap.structureColors[e.value] ?? const Color.fromRGBO(255, 0, 255, 1);
      final rect = Rect.fromCenter(center: at, width: r * 2, height: r * 2);
      canvas.drawRect(rect, _p(col));
      canvas.drawRect(rect, ring);
      if (labels) Hud.text(canvas, WorldMap.structureNames[e.value] ?? '?', at + Offset(r + 3, 4), size: 12, color: col);
    }
    for (final e in game.waypoints.entries) {
      final x = e.key.x.toDouble(), z = e.key.z.toDouble();
      if (!inside(x, z)) continue;
      final at = toScreen(x, z);
      final r = 4.5 * scale;
      canvas.drawPath(
          Path()
            ..moveTo(at.dx, at.dy - r)
            ..lineTo(at.dx + r, at.dy)
            ..lineTo(at.dx, at.dy + r)
            ..lineTo(at.dx - r, at.dy)
            ..close(),
          _p(WorldMap.waypointColor));
      if (labels) Hud.text(canvas, e.value, at + Offset(6 * scale, 4), size: 12, color: WorldMap.waypointColor);
    }
    for (final m in game.tamedMounts()) {
      if (!inside(m.position.x, m.position.z)) continue;
      final at = toScreen(m.position.x, m.position.z);
      canvas.drawCircle(at, 3.0 * scale, _p(WorldMap.mountColor));
      canvas.drawCircle(
          at,
          3.0 * scale,
          Paint()
            ..color = const Color.fromRGBO(255, 230, 179, 1)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0);
      if (labels) Hud.text(canvas, m.displayName(), at + Offset(6 * scale, 16), size: 12, color: const Color.fromRGBO(230, 191, 128, 1));
    }
  }

  /// Every living thing, through the same [toScreen] the ground is drawn with,
  /// so a creature keeps the patch of map it is standing on. [r] is the dot's
  /// radius.
  void _drawEntities(Canvas canvas, Offset Function(double x, double z) toScreen, bool Function(double x, double z) inside, double r) {
    for (final m in game.mobs) {
      if (!inside(m.position.x, m.position.z)) continue;
      canvas.drawCircle(toScreen(m.position.x, m.position.z), r,
          _p(m.species.hostile ? const Color.fromRGBO(255, 77, 77, 1) : const Color.fromRGBO(102, 255, 102, 1)));
    }
    for (final m in game.pets) {
      if (!inside(m.position.x, m.position.z)) continue;
      canvas.drawCircle(toScreen(m.position.x, m.position.z), r, _p(const Color.fromRGBO(102, 153, 255, 1)));
    }
  }

  /// The map, the same for both frames: the bitmap, the markers, the
  /// creatures and the player's arrow, all through [f] and clipped to its
  /// window. [icon] sizes what is drawn on top; [labels] names it.
  void _drawMap(Canvas canvas, MapFrame f, double icon, bool labels) {
    canvas.save();
    canvas.clipRect(f.view);
    canvas.drawRect(f.view, _p(const Color.fromRGBO(13, 13, 20, 1)));
    final img = worldMap.image;
    if (img != null) {
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          f.imageRect(worldMap.originX, worldMap.originZ, img.width, img.height), Paint()..filterQuality = FilterQuality.none);
    }
    _drawMarkers(canvas, f.toScreen, f.inside, icon, labels);
    _drawEntities(canvas, f.toScreen, f.inside, 2.5 * icon);
    final player = game.player;
    final pc = f.toScreen(player.position.x, player.position.z);
    final fwd = player.forward;
    final len = 9.0 * icon, half = 4.0 * icon;
    canvas.drawPath(
        Path()
          ..moveTo(pc.dx + fwd.x * len, pc.dy + fwd.z * len)
          ..lineTo(pc.dx - fwd.z * half, pc.dy + fwd.x * half)
          ..lineTo(pc.dx + fwd.z * half, pc.dy - fwd.x * half)
          ..close(),
        _p(Colors.white));
    if (labels) Hud.text(canvas, 'You', pc + const Offset(-10, -12), size: 12);
    canvas.restore();
  }

  /// The corner frame: a 96-block window of the map, centred on the player.
  void _drawCornerMap(Canvas canvas, Size size) {
    const ms = 240.0;
    final view = Rect.fromLTWH(size.width - ms - 20, 80, ms, ms);
    canvas.drawRect(view.inflate(3), _p(const Color.fromRGBO(0, 0, 0, 0.7)));
    final p = game.player.position;
    _drawMap(canvas, MapFrame(view, p.x, p.z, cornerScale), 1.0, false);
    Hud.text(
        canvas,
        'N up · red hostile · green passive · blue pet · cyan waypoint · brown mount · white spawn · squares structures · M again: full map',
        Offset(view.left, view.bottom + 16),
        size: 11,
        color: const Color.fromRGBO(204, 204, 204, 1),
        width: ms);
  }

  /// Pixels per block in the corner: 96 blocks across its 240 px.
  static const double cornerScale = 2.5;

  /// The full frame: the whole bitmap fitted into the panel.
  void _drawFullMap(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _p(const Color.fromRGBO(0, 0, 0, 0.7)));
    // The Godot panel is 1040x760; a smaller window scales it down.
    final k = math.min(1.0, math.min((size.width - 20) / 1040, (size.height - 20) / 760));
    canvas.save();
    canvas.translate(size.width * 0.5 - 520 * k, size.height * 0.5 - 380 * k);
    canvas.scale(k);
    const panel = Rect.fromLTWH(0, 0, 1040, 760);
    canvas.drawRect(panel, _p(Hud._c(0.08, 0.08, 0.1, 0.96)));
    canvas.drawRect(panel, Paint()
      ..color = Hud._c(0.6, 0.6, 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0);
    Hud.text(canvas, 'World map', const Offset(20, 32), size: 22);
    Hud.text(canvas, 'M: close · explored ${game.visitedChunks.length} chunks · grey = visited, out of view · red hostile · green passive · blue pet',
        const Offset(20, 52), size: 13, color: Hud._c(0.7, 0.7, 0.7));
    final img = worldMap.image;
    if (img != null) {
      final area = Rect.fromLTWH(20, 64, panel.width - 40, panel.height - 110);
      final iw = img.width.toDouble(), ih = img.height.toDouble();
      final s = math.min(area.width / iw, area.height / ih);
      final shown = Rect.fromCenter(center: area.center, width: iw * s, height: ih * s);
      canvas.drawRect(shown.inflate(2), _p(const Color.fromRGBO(0, 0, 0, 0.8)));
      _drawMap(canvas, MapFrame(shown, worldMap.originX + iw * 0.5, worldMap.originZ + ih * 0.5, s), 1.6, true);
    }
    // Legend
    final ly = panel.bottom - 30;
    const lx = 20.0;
    final grey = Hud._c(0.85, 0.85, 0.85);
    canvas.drawCircle(Offset(lx + 5, ly), 4.0, _p(WorldMap.spawnColor));
    Hud.text(canvas, 'spawn', Offset(lx + 14, ly + 4), size: 12, color: grey);
    final d = Offset(lx + 75, ly);
    canvas.drawPath(
        Path()
          ..moveTo(d.dx, d.dy - 5)
          ..lineTo(d.dx + 5, d.dy)
          ..lineTo(d.dx, d.dy + 5)
          ..lineTo(d.dx - 5, d.dy)
          ..close(),
        _p(WorldMap.waypointColor));
    Hud.text(canvas, 'waypoint', Offset(lx + 84, ly + 4), size: 12, color: grey);
    canvas.drawCircle(Offset(lx + 165, ly), 4.0, _p(WorldMap.mountColor));
    Hud.text(canvas, 'mount', Offset(lx + 174, ly + 4), size: 12, color: grey);
    var sx = lx + 240;
    for (var kind = 1; kind <= 8; kind++) {
      canvas.drawRect(Rect.fromLTWH(sx - 4, ly - 4, 8, 8), _p(WorldMap.structureColors[kind]!));
      Hud.text(canvas, WorldMap.structureNames[kind]!, Offset(sx + 7, ly + 4), size: 12, color: grey);
      sx += 22 + WorldMap.structureNames[kind]!.length * 7;
    }
    canvas.restore();
  }

  /// Stage 32 fix: the camera of THIS frame. The painter used to keep the one
  /// handed over when the widget was built, so mob bars and damage numbers were
  /// projected from wherever the player stood at that build.
  Offset? _project(vm.Vector3 world, Size size) => game.player.camera().worldToScreen(world, size);

  void _bar(Canvas c, double x, double y, double w, double h, double ratio, Color color, String label) {
    c.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.55));
    c.drawRect(Rect.fromLTWH(x + 2, y + 2, (w - 4) * ratio.clamp(0.0, 1.0), h - 4), Paint()..color = color);
    Hud.text(c, label, Offset(x + 8, y + h - 6), size: 15);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!game.ready) return;
    final player = game.player;
    final c = Offset(size.width * 0.5, size.height * 0.5);
    // The camera's eye inside a liquid: a blue wash over the screen (the fog does
    // the distance), an orange one in lava.
    switch (game.eyeLiquid) {
      case 'water':
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color.fromRGBO(16, 64, 150, 0.22));
      case 'lava':
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color.fromRGBO(210, 70, 0, 0.55));
    }
    // Stage 32: the red vignette (Godot's radial GradientTexture2D stretched over
    // the screen: clear to 45% of the half-height, 0.85 red at the edge and past
    // it) — a hit fades it over 0.4 s, low health keeps it pulsing.
    final va = game.hud.vignetteAlpha();
    if (va > 0.0) {
      final a = va.clamp(0.0, 1.0);
      final h = size.height;
      canvas.save();
      canvas.translate(size.width * 0.5, h * 0.5);
      canvas.scale(size.width / h, 1.0);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: h, height: h),
          Paint()
            ..shader = ui.Gradient.radial(Offset.zero, h * 0.5,
                [const Color.fromRGBO(204, 0, 0, 0.0), Color.fromRGBO(204, 0, 0, 0.85 * a)], const [0.45, 1.0]));
      canvas.restore();
    }
    if (player.damageFlash > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(200, 0, 0, 0.25 * player.damageFlash));
    }
    // Projected world labels: mob bars, damage numbers, puppets.
    for (final mob in [...game.mobs, ...game.pets]) {
      if (!mob.barVisible || mob.isDead) continue;
      final p = _project(mob.position + vm.Vector3(0, mob.height + 0.35, 0), size);
      if (p == null) continue;
      final dist = (mob.position - player.position).length;
      if (dist > 40) continue;
      final w = (60.0 * (8.0 / math.max(dist, 4.0))).clamp(28.0, 90.0);
      final h = w * 0.12;
      canvas.drawRect(Rect.fromCenter(center: p, width: w, height: h), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.7));
      final ratio = (mob.hp / mob.maxHp).clamp(0.0, 1.0);
      final bc = mob.barColor();
      final fill = mob.species.hostile || mob.tamed || mob.affix != ''
          ? Color.fromRGBO((bc.x * 255).round(), (bc.y * 255).round(), (bc.z * 255).round(), 1)
          : const Color.fromRGBO(77, 217, 77, 1);
      canvas.drawRect(Rect.fromLTWH(p.dx - w * 0.48, p.dy - h * 0.33, w * 0.96 * ratio, h * 0.66), Paint()..color = fill);
    }
    for (final n in game.damageNumbers) {
      // Stage 32: 1 m over 0.8 s, fading from 0.2 s to 1.0 s.
      final t = (n.age / DamageNumber.riseSeconds).clamp(0.0, 1.0);
      final rise = DamageNumber.rise * (1 - math.pow(1 - t, 2));
      final p = _project(n.pos + vm.Vector3(0, rise, 0), size);
      if (p == null) continue;
      final fadeFor = DamageNumber.lifetime - DamageNumber.fadeDelay;
      final alpha = n.age < DamageNumber.fadeDelay ? 1.0 : (1.0 - (n.age - DamageNumber.fadeDelay) / fadeFor).clamp(0.0, 1.0);
      final dist = (n.pos - player.position).length;
      final fs = (26.0 * (6.0 / math.max(dist, 3.0))).clamp(12.0, 34.0);
      Hud.text(canvas, n.text, Offset(p.dx - fs * 0.3 * n.text.length, p.dy), size: fs, color: Hud._c(n.color.x, n.color.y, n.color.z, alpha), weight: FontWeight.bold);
    }
    for (final pup in game.puppets) {
      final p = _project(pup.position + vm.Vector3(0, 2.1, 0), size);
      if (p == null) continue;
      Hud.text(canvas, pup.title, Offset(p.dx - 30, p.dy), size: 14, align: TextAlign.center, width: 60);
    }
    // Crosshair
    final col = player.aimedMob != null ? const Color.fromRGBO(255, 77, 77, 1) : Colors.white;
    final cp = Paint()..color = col..strokeWidth = 2;
    canvas.drawLine(c + const Offset(-9, 0), c + const Offset(-3, 0), cp);
    canvas.drawLine(c + const Offset(3, 0), c + const Offset(9, 0), cp);
    canvas.drawLine(c + const Offset(0, -9), c + const Offset(0, -3), cp);
    canvas.drawLine(c + const Offset(0, 3), c + const Offset(0, 9), cp);
    if (player.mineProgress > 0.0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: 16), -math.pi / 2, math.pi * 2 * player.mineProgress, false,
          Paint()..color = const Color.fromRGBO(255, 255, 255, 0.9)..strokeWidth = 3..style = PaintingStyle.stroke);
    }

    // Stats: bottom left, unless the on-screen controls are up — then the
    // bottom-left corner is the movement stick's and the column moves to the
    // top, clear of the pause button.
    final x = game.touchControls ? 70.0 : 20.0;
    final y = game.touchControls ? 14.0 : size.height - 150.0;
    _bar(canvas, x, y, 260, 24, player.hp / player.maxHp, const Color.fromRGBO(217, 38, 51, 1), 'HP ${player.hp.ceil()} / ${player.maxHp.toInt()}');
    _bar(canvas, x, y + 28, 260, 20, player.stamina / player.maxStamina, const Color.fromRGBO(64, 191, 64, 1), 'Stamina');
    _bar(canvas, x, y + 52, 260, 20, player.mana / player.maxMana, const Color.fromRGBO(77, 115, 242, 1), 'Mana ${player.mana.toInt()}');
    _bar(canvas, x, y + 76, 260, 20, player.hunger / 20.0, const Color.fromRGBO(217, 140, 51, 1), 'Food');
    // Stage 32: the XP fill tweens.
    _bar(canvas, x, y + 100, 260, 18, game.hud.xpShown(game), const Color.fromRGBO(191, 153, 242, 1),
        'Lv ${player.level}  ${player.classDef.name}   XP ${player.xp}/${player.xpToNext()}');
    // Ability
    final ab = player.classDef.ability;
    final ready = player.abilityCooldown <= 0.0;
    canvas.drawRect(Rect.fromLTWH(x + 270, y + 100, 150, 18), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.55));
    Hud.text(canvas, '[R] $ab${ready ? '' : ' (${player.abilityCooldown.round()}s)'}', Offset(x + 276, y + 114),
        size: 14, color: ready ? const Color.fromRGBO(255, 255, 153, 1) : const Color.fromRGBO(179, 179, 179, 1));
    // Stage 23: the second ability under the first.
    final ab2 = player.classDef.ability2;
    final ready2 = player.ability2Cooldown <= 0.0;
    canvas.drawRect(Rect.fromLTWH(x + 270, y + 122, 150, 18), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.55));
    Hud.text(canvas, '[Q] $ab2${ready2 ? '' : ' (${player.ability2Cooldown.round()}s)'}', Offset(x + 276, y + 136),
        size: 14, color: ready2 ? const Color.fromRGBO(179, 230, 255, 1) : const Color.fromRGBO(179, 179, 179, 1));

    if (player.talentPoints > 0) {
      Hud.text(canvas, '[J] ${player.talentPoints} talent point${player.talentPoints == 1 ? '' : 's'}',
          Offset(x + 270, y + 94), size: 14, color: const Color.fromRGBO(255, 230, 128, 1));
    }
    // Status effects, stacked away from the bars: above them at the bottom of
    // the screen, below them at the top.
    final estep = game.touchControls ? 26.0 : -26.0;
    var ey = game.touchControls ? y + 148.0 : y - 30.0;
    for (final id in player.effects.rows.keys) {
      final d = StatusEffects.def(id);
      final left = player.effects.timeLeft(id);
      final col = Color.fromRGBO((d.r * 255).round(), (d.g * 255).round(), (d.b * 255).round(), 1);
      canvas.drawRect(Rect.fromLTWH(x, ey, 200, 22), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.55));
      canvas.drawRect(Rect.fromLTWH(x, ey, 6, 22), Paint()..color = col);
      Hud.text(canvas, '${d.name}  ${left.ceil()}s', Offset(x + 12, ey + 16),
          size: 13, color: d.bad ? col : Colors.white);
      ey += estep;
    }

    // Hotbar (bottom centre)
    final hy = Hud.hotbarSlotRect(size, 0).top;
    for (var i = 0; i < 9; i++) {
      var r = Hud.hotbarSlotRect(size, i);
      if (i == player.selectedSlot) {
        // Stage 32: the selection tween.
        final k = game.hud.slotScale;
        r = Rect.fromCenter(center: r.center, width: r.width * k, height: r.height * k);
      }
      canvas.drawRect(r, Paint()..color = const Color.fromRGBO(0, 0, 0, 0.55));
      if (i == player.selectedSlot) {
        canvas.drawRect(r, Paint()..color = const Color.fromRGBO(255, 255, 255, 0.9)..style = PaintingStyle.stroke..strokeWidth = 3);
      }
      final id = player.inventory.idAt(i);
      if (id != '') {
        Hud.drawItemIcon(canvas, r, id);
        final n = player.inventory.countAt(i);
        if (n > 1) Hud.text(canvas, '$n', Offset(r.left + 4, r.bottom - 6), size: 14);
        if (player.inventory.bonusAt(i) > 0) {
          canvas.drawRect(r, Paint()..color = Hud.rarityColor(player.inventory.bonusAt(i))..style = PaintingStyle.stroke..strokeWidth = 2);
        }
        // Stage 23: a worn tool shows what is left of it under the icon.
        final maxDur = Items.durabilityOf(id);
        final dur = player.inventory.durAt(i);
        if (maxDur > 0 && dur < maxDur) {
          final ratio = dur / maxDur;
          canvas.drawRect(Rect.fromLTWH(r.left + 5, r.bottom - 7, r.width - 10, 4), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.8));
          canvas.drawRect(Rect.fromLTWH(r.left + 5, r.bottom - 7, (r.width - 10) * ratio, 4),
              Paint()..color = Color.fromRGBO(((1.0 - ratio) * 255).round(), (ratio * 255).round(), 38, 1));
        }
      }
    }
    final held = player.heldItem();
    if (held != '') {
      final bonus = player.inventory.bonusAt(player.selectedSlot);
      Hud.text(canvas, Hud.itemLabel(held, bonus), Offset(c.dx - 200, hy - 8), size: 16, align: TextAlign.center, width: 400, color: Hud.rarityColor(bonus));
    }

    // Time (top centre)
    Hud.text(canvas, game.timeLabel(), Offset(c.dx - 100, 26), size: 16, align: TextAlign.center, width: 200);

    // Notifications (right)
    var ny = size.height * 0.35;
    for (final n in game.notes) {
      final a = n.t.clamp(0.0, 1.0);
      Hud.text(canvas, n.text, Offset(size.width - 330, ny), size: 17, align: TextAlign.right, width: 310, color: Color.fromRGBO(255, 255, 255, a));
      ny += 22;
    }

    // Aimed mob name
    final am = player.aimedMob;
    if (am != null) {
      Hud.text(canvas, '${am.displayName()}  ${am.hp.ceil()}/${am.maxHp.toInt()}', Offset(c.dx - 150, c.dy - 40),
          size: 16, align: TextAlign.center, width: 300, color: const Color.fromRGBO(255, 204, 204, 1));
    } else if (game.playground != null && player.isAiming) {
      // Stage 33: the playground names the block under the crosshair.
      final aimed = game.world.getBlock(player.aimedBlock);
      if (aimed != Blocks.air) {
        Hud.text(canvas, Blocks.displayName(aimed), Offset(c.dx - 150, c.dy - 40),
            size: 15, align: TextAlign.center, width: 300, color: const Color.fromRGBO(204, 230, 255, 1));
      }
    }

    // Boss bar (stage 32: a portrait block in the species' colour, and it shakes on a hit)
    final boss = game.boss;
    if (boss != null && !boss.removed) {
      const bw = 500.0;
      final bx = c.dx - bw * 0.5 + game.hud.shakeJitter(6.0);
      final by = 44.0 + game.hud.shakeJitter(3.0);
      final pc = boss.species.colors[0];
      canvas.drawRect(Rect.fromLTWH(bx - 30, by - 4, 30, 30), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.7));
      canvas.drawRect(Rect.fromLTWH(bx - 27, by - 1, 24, 24), Paint()..color = Hud._c(pc.x, pc.y, pc.z));
      _bar(canvas, bx, by, bw, 22, boss.hp / boss.maxHp, const Color.fromRGBO(179, 26, 128, 1),
          '${boss.displayName()}   ${boss.hp.ceil()} / ${boss.maxHp.toInt()}');
    }
    // Stage 32: pickup toasts, bottom-right, newest at the bottom.
    var ty = size.height - (game.touchControls ? 170.0 : 90.0);
    for (var i = game.hud.toasts.length - 1; i >= 0; i--) {
      final t = game.hud.toasts[i];
      final a = t.t.clamp(0.0, 1.0);
      canvas.drawRect(Rect.fromLTWH(size.width - 230, ty - 18, 210, 24), Paint()..color = Color.fromRGBO(0, 0, 0, 0.5 * a));
      Hud.text(canvas, '+${t.n} ${Items.displayName(t.id)}', Offset(size.width - 224, ty + 2), size: 16, color: Color.fromRGBO(255, 255, 191, a));
      ty -= 28.0;
    }
    // Quest (top right)
    final q = game.quests.current;
    if (q != null) {
      final qx = size.width - 330;
      canvas.drawRect(Rect.fromLTWH(qx, 14, 316, 54), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.5));
      Hud.text(canvas, 'Quest: ${q.title}', Offset(qx + 10, 34), size: 15, color: const Color.fromRGBO(255, 230, 153, 1));
      Hud.text(canvas, '${q.text}  (${game.quests.progress}/${q.n})', Offset(qx + 10, 56), size: 13);
    }
    // The map (M): one frame or none, never both.
    switch (game.mapView) {
      case MapView.off:
        break;
      case MapView.corner:
        _drawCornerMap(canvas, size);
      case MapView.full:
        _drawFullMap(canvas, size);
    }
    final devAt = game.touchControls ? const Offset(12, 172) : const Offset(12, 22);
    if (game.debugVisible) {
      Hud.text(canvas, game.debugText(), devAt, size: 13, color: const Color.fromRGBO(255, 255, 255, 0.85));
    } else if (Settings.instance.showFps) {
      Hud.text(canvas, 'FPS ${game.fps.round()}', devAt, size: 13, color: const Color.fromRGBO(255, 255, 153, 0.9));
    }
  }

  @override
  bool shouldRepaint(covariant HudPainter old) => true;
}
