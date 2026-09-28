import 'dart:math' as math;
import 'dart:typed_data';

import 'package:voxel_engine/core.dart';

/// Chunk surfaces in the 16-byte vertex that `shaders/terrain.vert` unpacks.
/// [of] packs one chunk's [MeshSurface] in its own frame, once, when its mesh
/// arrives; [merge] moves several of them to their offsets in a region with
/// integer additions, so one `TerrainGeometry` draws them all and a region's
/// rebuild copies words instead of packing floats again.
///
/// A vertex is two streams of two 32-bit words, so the depth passes, which read
/// only the first, fetch 8 bytes a vertex:
///
/// * [positions]: `x | z << 16`, then `y`, each in 1/[positionScale] of a
///   metre from the chunk's (after [merge], the region's) corner, 0 up to 256 m.
/// * [attributes]: `r | g << 8 | b << 16 | a << 24`, the colour's square root in
///   rgb (so a dark, AO-shaded corner keeps its precision) and alpha as it is;
///   then `nx | ny << 8 | nz << 16 | sky << 24 | block << 28`, the normal biased
///   by 128 in 1/127 steps and the two light levels 0..15.
///
/// A whole number of metres is a whole number of steps, so packing a chunk and
/// then moving it lands on the same bits as packing it already moved.
class PackedSurface {
  PackedSurface._(this.positions, this.attributes, this.indices, this.minY, this.maxY);

  /// Steps a metre in a packed position.
  static const int positionScale = 256;

  /// [surface] packed in its chunk's frame, or null when it is empty. Indices
  /// are 16-bit while the vertices fit, 32-bit after.
  static PackedSurface? of(MeshSurface surface) {
    final vertices = surface.vertexCount;
    if (vertices == 0) return null;
    final positions = Uint32List(vertices * 2);
    final attributes = Uint32List(vertices * 2);
    final List<int> indices = vertices <= 0x10000
        ? Uint16List.fromList(surface.indices)
        : Uint32List.fromList(surface.indices);
    var minY = double.infinity, maxY = double.negativeInfinity;
    final p = surface.positions, n = surface.normals, c = surface.colors, l = surface.light;
    for (var j = 0; j < vertices; j++) {
      final y = p[j * 3 + 1];
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      positions[j * 2] = _fixed(p[j * 3], ChunkSize.sizeX) | _fixed(p[j * 3 + 2], ChunkSize.sizeZ) << 16;
      positions[j * 2 + 1] = _fixed(y, ChunkSize.sizeY);
      attributes[j * 2] =
          _sqrtUnorm8(c[j * 4]) |
          _sqrtUnorm8(c[j * 4 + 1]) << 8 |
          _sqrtUnorm8(c[j * 4 + 2]) << 16 |
          _unorm8(c[j * 4 + 3]) << 24;
      attributes[j * 2 + 1] =
          _snorm8(n[j * 3]) |
          _snorm8(n[j * 3 + 1]) << 8 |
          _snorm8(n[j * 3 + 2]) << 16 |
          _level(l[j * 2]) << 24 |
          _level(l[j * 2 + 1]) << 28;
    }
    return PackedSurface._(positions, attributes, indices, minY, maxY);
  }

  /// [parts] in order, each packed by [of] and moved by its offset in chunks,
  /// or null when there are none. The region must stay under 256 m a side.
  static PackedSurface? merge(List<(ChunkPos, PackedSurface)> parts) {
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
      assert(
        (offset.x + 1) * ChunkSize.sizeX * positionScale <= 0xFFFF &&
            (offset.z + 1) * ChunkSize.sizeZ * positionScale <= 0xFFFF,
        'a packed region spans 256 m: chunk offset $offset',
      );
      final shift = offset.x * ChunkSize.sizeX * positionScale | offset.z * ChunkSize.sizeZ * positionScale << 16;
      final p = s.positions;
      for (var j = 0; j < p.length; j += 2) {
        positions[v * 2 + j] = p[j] + shift;
        positions[v * 2 + j + 1] = p[j + 1];
      }
      attributes.setRange(v * 2, v * 2 + s.attributes.length, s.attributes);
      for (final i in s.indices) {
        indices[k++] = i + v;
      }
      if (s.minY < minY) minY = s.minY;
      if (s.maxY > maxY) maxY = s.maxY;
      v += s.vertexCount;
    }
    return PackedSurface._(positions, attributes, indices, minY, maxY);
  }

  /// A coordinate in 1/[positionScale] m, 0 up to [size] m.
  static int _fixed(double m, int size) {
    final q = (m * positionScale).round();
    assert(q >= 0 && q <= size * positionScale, 'a terrain vertex lies outside its chunk\'s 0..$size m: $m');
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

  /// Six per face: a `Uint16List` or a `Uint32List`.
  final List<int> indices;

  /// Vertices in [positions].
  int get vertexCount => positions.length ~/ 2;

  /// The lowest vertex height.
  final double minY;

  /// The highest vertex height.
  final double maxY;
}
