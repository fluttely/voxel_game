import '../core/chunk_writer.dart';
import '../core/world_math.dart';

/// Draws one structure into one chunk.
typedef StructureBuild = void Function(StructureSite site);

/// What a [StructureBuild] draws with: a site in the world and the chunk being
/// generated. Coordinates are relative to the site ([x], [y], [z]) — the
/// surface, or [depth] under it — and every write outside the chunk is
/// dropped, so the builder draws the whole structure every time and each
/// chunk keeps its own part.
class StructureSite {
  /// A site at world ([x], [y], [z]) drawing into [writer].
  StructureSite({
    required this.name,
    required this.x,
    required this.y,
    required this.z,
    required this.seed,
    required this.writer,
    required this._block,
    required this._surfaceAt,
  });

  /// The structure's name.
  final String name;

  /// The site, in world coordinates.
  final int x, y, z;

  /// The world seed.
  final int seed;

  /// The chunk being generated.
  final ChunkWriter writer;

  final int Function(String name) _block;
  final int Function(int x, int z) _surfaceAt;
  final Map<String, int> _ids = {};

  /// The id of block [name].
  int block(String name) => _ids[name] ??= _block(name);

  /// A roll of this site, the same in every chunk: a hash of the site and
  /// [salt]. Take `roll(n) % k` for a choice among k.
  int roll(int salt) => worldHash(seed, x, salt, z);

  /// The surface height (first air cell) at site-relative ([dx], [dz]), in
  /// site-relative y.
  int surfaceAt(int dx, int dz) => _surfaceAt(x + dx, z + dz) - y;

  /// Puts [name] at site-relative ([dx], [dy], [dz]); `'air'` clears.
  void put(int dx, int dy, int dz, String name) => writer.put(x + dx, y + dy, z + dz, name == 'air' ? 0 : block(name));

  /// The block at site-relative ([dx], [dy], [dz]), or null outside the chunk.
  int? get(int dx, int dy, int dz) => writer.get(x + dx, y + dy, z + dz);

  /// Fills the site-relative box ([x0], [y0], [z0])..([x1], [y1], [z1]),
  /// inclusive, with [name]; [hollow] leaves the inside as air.
  void fill(int x0, int y0, int z0, int x1, int y1, int z1, String name, {bool hollow = false}) {
    final id = name == 'air' ? 0 : block(name);
    for (var yy = y0; yy <= y1; yy++) {
      for (var zz = z0; zz <= z1; zz++) {
        for (var xx = x0; xx <= x1; xx++) {
          final edge = xx == x0 || xx == x1 || yy == y0 || yy == y1 || zz == z0 || zz == z1;
          writer.put(x + xx, y + yy, z + zz, hollow && !edge ? 0 : id);
        }
      }
    }
  }

  /// Sits a floor on a slope: every column of the site-relative rectangle
  /// ([x0], [z0])..([x1], [z1]) is filled with [foundation] from its ground up
  /// to under dy 0 and cleared from dy 1 up to [clearTo].
  void level(int x0, int z0, int x1, int z1, String foundation, {int clearTo = 6}) {
    final id = block(foundation);
    for (var zz = z0; zz <= z1; zz++) {
      for (var xx = x0; xx <= x1; xx++) {
        writer.levelColumn(x + xx, z + zz, _surfaceAt(x + xx, z + zz), y, y + clearTo, id);
      }
    }
  }

  /// Draws [layers] bottom to top, each a list of rows along +z, each row a
  /// string along +x, with [legend] naming the block of each character; a
  /// space or a character not in the legend leaves the cell alone, `'.'`
  /// clears it. The first cell of the first row of the first layer lands at
  /// site-relative ([dx], [dy], [dz]).
  ///
  /// ```dart
  /// site.blueprint([
  ///   ['###', '###', '###'],
  ///   ['#.#', '...', '#.#'],
  /// ], {'#': 'cobblestone'}, dx: -1, dz: -1);
  /// ```
  void blueprint(List<List<String>> layers, Map<String, String> legend, {int dx = 0, int dy = 0, int dz = 0}) {
    for (var ly = 0; ly < layers.length; ly++) {
      final rows = layers[ly];
      for (var rz = 0; rz < rows.length; rz++) {
        final row = rows[rz];
        for (var rx = 0; rx < row.length; rx++) {
          final ch = row[rx];
          if (ch == '.') {
            writer.put(x + dx + rx, y + dy + ly, z + dz + rz, 0);
            continue;
          }
          final name = legend[ch];
          if (name == null) continue;
          put(dx + rx, dy + ly, dz + rz, name);
        }
      }
    }
  }
}
