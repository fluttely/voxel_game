import 'dart:typed_data';

import '../core/chunk_writer.dart';

/// A scratch volume a tree is drawn on before it is printed into a chunk.
///
/// Why draw first: [print] walks the six faces outward from the blocks
/// standing on the ground and keeps only what the walk reaches, so a frayed
/// leaf with nothing under it, a vine hanging off the air and a branch
/// touching the trunk by a corner alone all fall away before anyone sees them
/// float. The canvas is in world coordinates, so every hash a shape rolls is
/// the same in both chunks that share the tree, and both print the same tree.
///
/// Use: [begin] at the stump, draw with [ink] (or the shapes of `Trees`),
/// then [print] into the chunk being generated. One canvas per generator; it
/// is not reentrant.
class TreeCanvas {
  /// A canvas [radius] blocks around the stump and [height] tall. [isSoft]
  /// names leaves and vines: a log is drawn over them, nothing is drawn over a
  /// log. [groundAt] gives a column's surface height (the first air cell): the
  /// tree keeps out of the ground and out of anything at or under [floorY]
  /// (the sea). [hash] is the generator's positional hash, for the shapes.
  TreeCanvas({
    this.radius = 8,
    this.height = 40,
    required this.isSoft,
    required this.groundAt,
    required this.floorY,
    required this.hash,
  }) : _width = radius * 2 + 1,
       _layer = (radius * 2 + 1) * (radius * 2 + 1) {
    _canvas = Uint8List(_layer * height);
    _kept = Uint8List(_layer * height);
    _colHeight = Int32List(_layer);
    _colStamp = Int32List(_layer);
  }

  /// How far from the stump a block may be drawn, sideways.
  final int radius;

  /// How far above the stump a block may be drawn.
  final int height;

  /// Leaves and vines.
  final bool Function(int id) isSoft;

  /// A column's surface height.
  final int Function(int x, int z) groundAt;

  /// Nothing of a tree stays at or below this height.
  final int floorY;

  /// The positional hash shapes roll with.
  final int Function(int x, int y, int z) hash;

  final int _width, _layer;
  late final Uint8List _canvas, _kept;
  late final Int32List _colHeight, _colStamp;
  final List<int> _painted = <int>[];
  final List<int> _walk = <int>[];
  int _serial = 0;
  int _x = 0, _y = 0, _z = 0;

  /// Centres a new tree on world ([x], [y], [z]), its stump on the ground.
  void begin(int x, int y, int z) {
    _x = x;
    _y = y;
    _z = z;
    _serial++;
  }

  /// Paints one block of the tree, in world coordinates. Only a log is drawn
  /// over a leaf, and nothing over a log.
  void ink(int x, int y, int z, int id) {
    final dx = x - _x, dy = y - _y, dz = z - _z;
    if (dx < -radius || dx > radius || dz < -radius || dz > radius) return;
    if (dy < 0 || dy >= height) return;
    final i = (dy * _width + dz + radius) * _width + dx + radius;
    final cur = _canvas[i];
    if (cur == 0) {
      _painted.add(i);
    } else if (isSoft(id) || !isSoft(cur)) {
      return;
    }
    _canvas[i] = id;
  }

  /// What the canvas holds at a world position, 0 for nothing.
  int inked(int x, int y, int z) {
    final dx = x - _x, dy = y - _y, dz = z - _z;
    if (dx < -radius || dx > radius || dz < -radius || dz > radius) return 0;
    if (dy < 0 || dy >= height) return 0;
    return _canvas[(dy * _width + dz + radius) * _width + dx + radius];
  }

  bool _blockedAt(int i) {
    final dy = i ~/ _layer, col = i % _layer;
    final wy = _y + dy;
    if (wy <= floorY) return true;
    if (_colStamp[col] != _serial) {
      _colStamp[col] = _serial;
      _colHeight[col] = groundAt(_x + col % _width - radius, _z + col ~/ _width - radius);
    }
    return wy < _colHeight[col];
  }

  void _stepTo(int i, bool inside) {
    if (!inside || _canvas[i] == 0 || _kept[i] != 0 || _blockedAt(i)) return;
    _kept[i] = 1;
    _walk.add(i);
  }

  /// Keeps what holds together (a flood fill from the blocks on the ground),
  /// prints it into [w] over air and soft blocks, and wipes the canvas.
  void print(ChunkWriter w) {
    _walk.clear();
    for (final i in _painted) {
      if (i < _layer) _stepTo(i, true);
    }
    for (var q = 0; q < _walk.length; q++) {
      final i = _walk[q];
      final dy = i ~/ _layer, rest = i % _layer;
      final dz = rest ~/ _width, dx = rest % _width;
      _stepTo(i - 1, dx > 0);
      _stepTo(i + 1, dx < _width - 1);
      _stepTo(i - _width, dz > 0);
      _stepTo(i + _width, dz < _width - 1);
      _stepTo(i - _layer, dy > 0);
      _stepTo(i + _layer, dy < height - 1);
    }
    for (final i in _painted) {
      if (_kept[i] != 0) {
        final dy = i ~/ _layer, rest = i % _layer;
        final dz = rest ~/ _width, dx = rest % _width;
        w.place(_x + dx - radius - w.ox, _y + dy, _z + dz - radius - w.oz, _canvas[i], over: isSoft);
      }
      _canvas[i] = 0;
      _kept[i] = 0;
    }
    _painted.clear();
  }
}
