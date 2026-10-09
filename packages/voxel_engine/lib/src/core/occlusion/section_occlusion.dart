import 'dart:collection';
import 'dart:typed_data';

import '../streaming/chunk_streamer.dart';
import 'chunk_visibility.dart';

/// The chunks sight can reach from the camera through open cells: a
/// breadth-first search over 16-tall sections, from the camera's section,
/// crossing a section only between faces its [ChunkVisibility] joins and never
/// stepping against a direction the path has already taken (Checchi's cave
/// culling). A chunk is reached when any of its sections is.
///
/// The search has no frustum term, so its result depends only on the camera's
/// section, the window and the visibility data; [update] reruns it only when
/// one of those changed.
final class SectionOcclusion {
  /// A search reading each chunk's visibility from [visibilityOf]; a null is a
  /// chunk with no mesh yet, which occludes nothing and is crossed as open.
  SectionOcclusion(this.visibilityOf);

  /// The visibility of a chunk, or null when it has none.
  final ChunkVisibility? Function(ChunkPos pos) visibilityOf;

  static const int _sections = ChunkVisibility.sections;
  static const List<int> _dx = [-1, 1, 0, 0, 0, 0], _dy = [0, 0, -1, 1, 0, 0], _dz = [0, 0, 0, 0, -1, 1];

  final Set<ChunkPos> _reached = {};
  bool _changed = true;
  ChunkPos? _camera;
  int _section = -1;
  int _minX = 0, _minZ = 0, _maxX = -1, _maxZ = -1;

  // Per section of the window, indexed `(s * depth + z) * width + x` from the
  // window's corner: 1 once visited; the face it was entered by; the 6-bit set
  // of directions its path took. The queue holds those indices.
  Uint8List _visited = Uint8List(0), _faceIn = Uint8List(0), _dirs = Uint8List(0);
  Int32List _queue = Int32List(0);

  /// The section holding cell height [y]. A camera above the world looks into
  /// the top section and one below it into the bottom one, so those clamp.
  static int sectionAt(double y) => (y.floor() ~/ ChunkVisibility.sectionHeight).clamp(0, _sections - 1);

  /// The chunks the last run reached.
  Set<ChunkPos> get reached => UnmodifiableSetView(_reached);

  /// Chunk [pos] got, changed or lost its visibility: the next [update] reruns
  /// when it lies in the window the last run searched.
  void markChanged(ChunkPos pos) {
    if (pos.x >= _minX && pos.x <= _maxX && pos.z >= _minZ && pos.z <= _maxZ) _changed = true;
  }

  /// Searches from section [section] of chunk [camera] over the chunks from
  /// [min] to [max] (both inclusive), unless none of those inputs changed and
  /// no chunk was marked changed since the last run. True when it ran.
  bool update(ChunkPos camera, int section, {required ChunkPos min, required ChunkPos max}) {
    RangeError.checkValueInInterval(section, 0, _sections - 1, 'section');
    if (max.x < min.x || max.z < min.z) throw ArgumentError('the window from $min to $max is empty');
    if (camera.x < min.x || camera.x > max.x || camera.z < min.z || camera.z > max.z) {
      throw ArgumentError.value(camera, 'camera', 'outside the window from $min to $max');
    }
    final same =
        camera == _camera &&
        section == _section &&
        min.x == _minX &&
        min.z == _minZ &&
        max.x == _maxX &&
        max.z == _maxZ;
    if (same && !_changed) return false;
    _camera = camera;
    _section = section;
    _minX = min.x;
    _minZ = min.z;
    _maxX = max.x;
    _maxZ = max.z;
    _changed = false;
    _search(camera, section);
    return true;
  }

  void _search(ChunkPos camera, int section) {
    final width = _maxX - _minX + 1, depth = _maxZ - _minZ + 1;
    final volume = width * depth * _sections;
    if (_visited.length != volume) {
      _visited = Uint8List(volume);
      _faceIn = Uint8List(volume);
      _dirs = Uint8List(volume);
      _queue = Int32List(volume);
    } else {
      _visited.fillRange(0, volume, 0);
    }
    _reached.clear();
    final columns = Uint8List(width * depth);
    var tail = 0;

    // Enters the section next to (x, s, z) through face out, unless the search
    // already visited it or it lies past the window or the world.
    void step(int x, int s, int z, int out, int dirs) {
      final nx = x + _dx[out], ns = s + _dy[out], nz = z + _dz[out];
      if (ns < 0 || ns >= _sections || nx < 0 || nx >= width || nz < 0 || nz >= depth) return;
      final i = (ns * depth + nz) * width + nx;
      if (_visited[i] != 0) return;
      _visited[i] = 1;
      _faceIn[i] = out ^ 1;
      _dirs[i] = dirs | 1 << out;
      _queue[tail++] = i;
      columns[nz * width + nx] = 1;
    }

    final cx = camera.x - _minX, cz = camera.z - _minZ;
    _visited[(section * depth + cz) * width + cx] = 1;
    columns[cz * width + cx] = 1;
    for (var out = 0; out < 6; out++) {
      step(cx, section, cz, out, 0);
    }
    var head = 0;
    while (head < tail) {
      final i = _queue[head++];
      final x = i % width, z = (i ~/ width) % depth, s = i ~/ (width * depth);
      final faceIn = _faceIn[i], dirs = _dirs[i];
      final visibility = visibilityOf((x: x + _minX, z: z + _minZ));
      for (var out = 0; out < 6; out++) {
        if (dirs & 1 << (out ^ 1) != 0) continue;
        if (visibility != null && !visibility.connects(s, faceIn, out)) continue;
        step(x, s, z, out, dirs);
      }
    }
    for (var z = 0; z < depth; z++) {
      for (var x = 0; x < width; x++) {
        if (columns[z * width + x] != 0) _reached.add((x: x + _minX, z: z + _minZ));
      }
    }
  }
}
