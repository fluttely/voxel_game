import 'dart:math' as math;
import 'dart:typed_data';

import 'package:voxel_engine/core.dart';

/// Several chunks' [MeshSurface]s packed into the 16-byte vertex that
/// `shaders/terrain.vert` unpacks, each chunk moved by its offset in the region,
/// so one `TerrainGeometry` draws them all.
///
/// A vertex is two streams of two 32-bit words, so the depth passes, which read
/// only the first, fetch 8 bytes a vertex:
///
/// * [positions]: `x | z << 16`, then `y`, each in 1/[positionScale] of a
///   metre from the region's corner (0 up to 256 m).
/// * [attributes]: `r | g << 8 | b << 16 | a << 24`, the colour's square root in
///   rgb (so a dark, AO-shaded corner keeps its precision) and alpha as it is;
///   then `nx | ny << 8 | nz << 16 | sky << 24 | block << 28`, the normal biased
///   by 128 in 1/127 steps and the two light levels 0..15.
class PackedSurface {
  PackedSurface._(this.positions, this.attributes, this.indices, this.minY, this.maxY);

  /// Steps a metre in a packed position.
  static const int positionScale = 256;

  /// [parts] packed in order, each at its offset in chunks, or null when every
  /// part is empty. Indices are 16-bit while the vertices fit, 32-bit after.
  static PackedSurface? of(List<(ChunkPos, MeshSurface)> parts) {
    var vertices = 0, indexCount = 0;
    for (final (_, s) in parts) {
      vertices += s.vertexCount;
      indexCount += s.indices.length;
    }
    if (vertices == 0) return null;
    final positions = Uint32List(vertices * 2);
    final attributes = Uint32List(vertices * 2);
    final List<int> indices = vertices <= 0x10000 ? Uint16List(indexCount) : Uint32List(indexCount);
    var minY = double.infinity, maxY = double.negativeInfinity;
    var v = 0, k = 0;
    for (final (offset, s) in parts) {
      final ox = offset.x * ChunkSize.sizeX, oz = offset.z * ChunkSize.sizeZ;
      final p = s.positions, n = s.normals, c = s.colors, l = s.light;
      for (var j = 0; j < s.vertexCount; j++) {
        final y = p[j * 3 + 1];
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        positions[(v + j) * 2] = _fixed(p[j * 3] + ox) | _fixed(p[j * 3 + 2] + oz) << 16;
        positions[(v + j) * 2 + 1] = _fixed(y);
        attributes[(v + j) * 2] =
            _sqrtUnorm8(c[j * 4]) |
            _sqrtUnorm8(c[j * 4 + 1]) << 8 |
            _sqrtUnorm8(c[j * 4 + 2]) << 16 |
            _unorm8(c[j * 4 + 3]) << 24;
        attributes[(v + j) * 2 + 1] =
            _snorm8(n[j * 3]) |
            _snorm8(n[j * 3 + 1]) << 8 |
            _snorm8(n[j * 3 + 2]) << 16 |
            _level(l[j * 2]) << 24 |
            _level(l[j * 2 + 1]) << 28;
      }
      for (final i in s.indices) {
        indices[k++] = i + v;
      }
      v += s.vertexCount;
    }
    return PackedSurface._(positions, attributes, indices, minY, maxY);
  }

  /// A coordinate in 1/[positionScale] m, 16 bits.
  static int _fixed(double m) {
    final q = (m * positionScale).round();
    assert(q >= 0 && q <= 0xFFFF, 'a terrain vertex lies outside its region\'s 0..256 m: $m');
    return q;
  }

  /// The square root of a linear colour channel in 0..1, 8 bits.
  static int _sqrtUnorm8(double linear) {
    assert(linear >= 0.0 && linear <= 1.0, 'a terrain colour channel outside 0..1: $linear');
    return (math.sqrt(linear) * 255).round();
  }

  /// A value in 0..1, 8 bits.
  static int _unorm8(double x) {
    assert(x >= 0.0 && x <= 1.0, 'a terrain alpha outside 0..1: $x');
    return (x * 255).round();
  }

  /// A normal component in -1..1, 8 bits biased by 128.
  static int _snorm8(double x) {
    assert(x >= -1.0 && x <= 1.0, 'a terrain normal component outside -1..1: $x');
    return (x * 127).round() + 128;
  }

  /// A light level stored as level / 15, back to 0..15.
  static int _level(double fraction) {
    final level = (fraction * 15).round();
    assert((level - fraction * 15).abs() < 1e-3 && level >= 0 && level <= 15, 'a light level not in 0..15: $fraction');
    return level;
  }

  /// Two words per vertex: `x | z << 16`, `y`.
  final Uint32List positions;

  /// Two words per vertex: the colour, then the normal and the light.
  final Uint32List attributes;

  /// Six per face, offset to the merged vertices: a `Uint16List` or a `Uint32List`.
  final List<int> indices;

  /// Vertices in [positions].
  int get vertexCount => positions.length ~/ 2;

  /// The lowest vertex height.
  final double minY;

  /// The highest vertex height.
  final double maxY;
}
