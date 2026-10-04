import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:voxel_engine/core.dart' show ChunkPos, ChunkSize, ChunkStreamer;
import 'package:voxel_game/voxel_game.dart';

import 'world_map.dart';

/// The world as the map draws it: one pixel a block over every chunk loaded
/// and every one explored ([WorldMap.exploredIn]) within [reach] chunks of
/// the player, [unseen] where an explored chunk is not loaded. Each pixel is
/// the top block of its column shaded by its height, a liquid on it wins,
/// and a few biomes tint it ([colourAt]).
///
/// Kept a tile a chunk, refreshed for up to [sliceMs] a frame while the map
/// shows ([update]), the missing ones first, so a block edited or a chunk
/// loaded shows within a lap; composed into one [image] every
/// [composeEvery] seconds. The image is fixed to the world, its top-left at
/// block ([originX], [originZ]): the ground and everything on it move
/// together under the player.
class MapPicture {
  /// Chunks either side of the player's the picture covers: it never grows
  /// past 65 chunks a side.
  static const int reach = 32;

  /// What refreshing tiles may take a frame, in milliseconds.
  static const double sliceMs = 2.0;

  /// Seconds between two compositions of the image.
  static const double composeEvery = 1.0;

  /// Seconds idle between two laps over the tiles.
  static const double lapRest = 1.0;

  /// Seconds without an [update] after which the map counts as closed: the
  /// next one paints every missing tile at once and composes.
  static const double closedAfter = 0.25;

  /// An explored chunk out of the loaded ones.
  static const int unseen = 0x383842;

  /// A column with nothing in it.
  static const int empty = 0x0D0D14;

  /// The biomes that tint the ground, by name: a swamp reads murky, a jungle
  /// deep green, the underworld red.
  static const Map<String, int> biomeTint = {'swamp': 0x4D572E, 'jungle': 0x1A6B1F, 'underworld': 0x731414};

  /// How far a tint pulls the ground's colour towards it.
  static const double biomeTintWeight = 0.45;

  /// The composed picture, or null before the first composition.
  ui.Image? image;

  /// The world block at [image]'s top-left.
  int originX = 0, originZ = 0;

  final Map<ChunkPos, Uint8List> _tiles = {};
  final Map<int, String> _biomes = {};
  String? _dimension;
  List<ChunkPos> _queue = const [];
  int _next = 0;
  double _restUntil = 0.0, _composeAt = 0.0, _shownAt = -1.0;
  bool _busy = false;

  /// The colour (`0xRRGGBB`) of column ([x], [z]) of [game]'s world, which
  /// must be loaded. A biome is sampled once a 4x4 cell, kept in [biomes].
  static int colourAt(VoxelGame game, int x, int z, Map<int, String> biomes) {
    final world = game.world;
    final y = world.groundHeight(x, z) - 1;
    var (r, g, b) = (_r(empty), _g(empty), _b(empty));
    final id = world.getBlockXYZ(x, y, z);
    if (id != BlockRegistry.air) {
      final top = world.blocks[id];
      final shade = (0.55 + (y - 40) / 80.0).clamp(0.4, 1.2);
      (r, g, b) = (top.r * shade, top.g * shade, top.b * shade);
    }
    final above = world.blocks[world.getBlockXYZ(x, y + 1, z)];
    if (above.liquid != null) (r, g, b) = (above.r, above.g, above.b);
    final cx = x >> 2, cz = z >> 2;
    final biome = biomes[biomeCell(x, z)] ??= world.generator.biomeAt(cx << 2, cz << 2).name;
    if (biomeTint[biome] case final tint?) {
      r += (_r(tint) - r) * biomeTintWeight;
      g += (_g(tint) - g) * biomeTintWeight;
      b += (_b(tint) - b) * biomeTintWeight;
    }
    return (_byte(r) << 16) | (_byte(g) << 8) | _byte(b);
  }

  /// The key in [colourAt]'s biomes of the 4x4 cell column ([x], [z]) is
  /// in.
  static int biomeCell(int x, int z) => ((x >> 2) & 0xFFFFFF) | (((z >> 2) & 0xFFFFFF) << 24);

  /// The chunks the picture covers about [game]'s player: every one loaded
  /// and every one explored within [reach].
  static Set<ChunkPos> chunksOf(VoxelGame game) {
    final here = ChunkStreamer.chunkOf(IVec3.floor(game.player.position));
    bool near(ChunkPos c) => (c.x - here.x).abs() <= reach && (c.z - here.z).abs() <= reach;
    return {
      ...WorldMap.of(game).exploredIn(game.dimension).where(near),
      for (var x = here.x - reach; x <= here.x + reach; x++)
        for (var z = here.z - reach; z <= here.z + reach; z++)
          if (game.world.isLoaded(IVec3(x << ChunkSize.shiftX, 0, z << ChunkSize.shiftZ))) (x: x, z: z),
    };
  }

  /// Keeps the picture fresh for a frame of the map showing [game]: tiles
  /// for up to [sliceMs], and the image composed when it is due. The first
  /// frame after [closedAfter] without one paints every missing tile and
  /// composes at once. A trip to another dimension starts it over.
  void update(VoxelGame game) {
    final now = game.time;
    if (_dimension != game.dimension) {
      _dimension = game.dimension;
      _tiles.clear();
      _biomes.clear();
      _queue = const [];
      _next = 0;
      _shownAt = -1.0;
      image?.dispose();
      image = null;
    }
    final opened = _shownAt < 0.0 || now - _shownAt > closedAfter;
    _shownAt = now;
    if (opened) {
      _next = _queue.length;
      _refresh(game, fillMissing: true);
      _composeAt = now;
    } else if (now >= _restUntil || _next < _queue.length) {
      _refresh(game);
    }
    if (now < _composeAt || _busy) return;
    _composeAt = now + composeEvery;
    _compose();
  }

  // Refreshes tiles for up to [sliceMs]: the missing ones first, then the rest in turn. [fillMissing] paints every
  // missing tile whatever the time.
  void _refresh(VoxelGame game, {bool fillMissing = false}) {
    final clock = Stopwatch()..start();
    if (_next >= _queue.length) {
      final covered = chunksOf(game);
      _tiles.removeWhere((c, _) => !covered.contains(c));
      _queue = [...covered.where((c) => !_tiles.containsKey(c)), ...covered.where(_tiles.containsKey)];
      _next = 0;
      // A biome never changes: kept across laps, dropped once the player has wandered far enough to fill it.
      if (_biomes.length > 4 * 16 * covered.length) _biomes.clear();
    }
    while (_next < _queue.length &&
        (clock.elapsedMicroseconds < sliceMs * 1000.0 || (fillMissing && !_tiles.containsKey(_queue[_next])))) {
      final c = _queue[_next++];
      _tiles[c] = _paint(game, c, _tiles[c] ?? Uint8List(ChunkSize.sizeX * ChunkSize.sizeZ * 4));
    }
    if (_next >= _queue.length) _restUntil = game.time + lapRest;
  }

  Uint8List _paint(VoxelGame game, ChunkPos c, Uint8List px) {
    final x0 = c.x << ChunkSize.shiftX, z0 = c.z << ChunkSize.shiftZ;
    final loaded = game.world.isLoaded(IVec3(x0, 0, z0));
    for (var iz = 0; iz < ChunkSize.sizeZ; iz++) {
      for (var ix = 0; ix < ChunkSize.sizeX; ix++) {
        final rgb = loaded ? colourAt(game, x0 + ix, z0 + iz, _biomes) : unseen;
        final o = (iz * ChunkSize.sizeX + ix) * 4;
        px[o] = rgb >> 16;
        px[o + 1] = (rgb >> 8) & 0xFF;
        px[o + 2] = rgb & 0xFF;
        px[o + 3] = 0xFF;
      }
    }
    return px;
  }

  // Copies the tiles into one bitmap, transparent where there is none, and decodes it into the image.
  void _compose() {
    if (_tiles.isEmpty) return;
    var loX = 1 << 30, loZ = 1 << 30, hiX = -(1 << 30), hiZ = -(1 << 30);
    for (final c in _tiles.keys) {
      loX = math.min(loX, c.x);
      loZ = math.min(loZ, c.z);
      hiX = math.max(hiX, c.x);
      hiZ = math.max(hiZ, c.z);
    }
    const side = ChunkSize.sizeX;
    final w = (hiX - loX + 1) * side, h = (hiZ - loZ + 1) * side;
    final pixels = Uint8List(w * h * 4);
    for (final MapEntry(key: c, value: tile) in _tiles.entries) {
      final x0 = (c.x - loX) * side, z0 = (c.z - loZ) * side;
      for (var iz = 0; iz < side; iz++) {
        final at = ((z0 + iz) * w + x0) * 4;
        pixels.setRange(at, at + side * 4, tile, iz * side * 4);
      }
    }
    final ox = loX * side, oz = loZ * side, dimension = _dimension;
    _busy = true;
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, (img) {
      _busy = false;
      // Composed before a trip: the other dimension's.
      if (dimension != _dimension) return img.dispose();
      image?.dispose();
      image = img;
      originX = ox;
      originZ = oz;
    });
  }

  static double _r(int rgb) => ((rgb >> 16) & 0xFF) / 255.0;
  static double _g(int rgb) => ((rgb >> 8) & 0xFF) / 255.0;
  static double _b(int rgb) => (rgb & 0xFF) / 255.0;
  static int _byte(double v) => (v * 255).round().clamp(0, 255);
}
