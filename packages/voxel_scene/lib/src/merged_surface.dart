import 'dart:typed_data';

import 'package:voxel_engine/core.dart';

/// Several chunks' [MeshSurface]s as one vertex and index list, each chunk's
/// positions moved by its offset in the region, so one geometry draws them all.
class MergedSurface {
  MergedSurface._(this.positions, this.normals, this.colors, this.light, this.indices, this.minY, this.maxY);

  /// [parts] merged in order, each at its offset in chunks, or null when every
  /// part is empty. Indices are 16-bit while the vertices fit, 32-bit after.
  static MergedSurface? of(List<(ChunkPos, MeshSurface)> parts) {
    var vertices = 0, indexCount = 0;
    for (final (_, s) in parts) {
      vertices += s.vertexCount;
      indexCount += s.indices.length;
    }
    if (vertices == 0) return null;
    final positions = Float32List(vertices * 3);
    final normals = Float32List(vertices * 3);
    final colors = Float32List(vertices * 4);
    final light = Float32List(vertices * 2);
    final List<int> indices = vertices <= 0x10000 ? Uint16List(indexCount) : Uint32List(indexCount);
    var minY = double.infinity, maxY = double.negativeInfinity;
    var v = 0, k = 0;
    for (final (offset, s) in parts) {
      final ox = offset.x * ChunkSize.sizeX.toDouble(), oz = offset.z * ChunkSize.sizeZ.toDouble();
      final p = s.positions, base = v * 3;
      for (var j = 0; j < p.length; j += 3) {
        final y = p[j + 1];
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        positions[base + j] = p[j] + ox;
        positions[base + j + 1] = y;
        positions[base + j + 2] = p[j + 2] + oz;
      }
      normals.setRange(v * 3, v * 3 + s.normals.length, s.normals);
      colors.setRange(v * 4, v * 4 + s.colors.length, s.colors);
      light.setRange(v * 2, v * 2 + s.light.length, s.light);
      for (final i in s.indices) {
        indices[k++] = i + v;
      }
      v += s.vertexCount;
    }
    return MergedSurface._(positions, normals, colors, light, indices, minY, maxY);
  }

  /// Three floats per vertex, in the region's frame.
  final Float32List positions;

  /// Three floats per vertex.
  final Float32List normals;

  /// Four floats per vertex.
  final Float32List colors;

  /// Two floats per vertex: sky / 15 and block / 15.
  final Float32List light;

  /// Six per face, offset to the merged vertices: a `Uint16List` or a `Uint32List`.
  final List<int> indices;

  /// The lowest vertex height.
  final double minY;

  /// The highest vertex height.
  final double maxY;
}
