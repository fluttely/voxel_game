import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Boxes drawn as one mesh: a node and a draw for all of them, where a node a
/// box is a draw a box (flutter_scene draws each geometry apart). The faces
/// wind as the chunk mesher's, clockwise seen from the normal side, so the
/// mesh is seen through a `MirroredCamera` on a plain node, not a mirrored one.
abstract final class BoxMesh {
  /// The six faces of every box of [boxes], in order: four vertices and six
  /// indices a face, the normals flat.
  static ({Float32List positions, Float32List normals, Uint16List indices}) arrays(List<Aabb3> boxes) {
    assert(boxes.length * 24 <= 1 << 16, '${boxes.length} boxes overflow 16-bit indices');
    final positions = Float32List(boxes.length * 72);
    final normals = Float32List(boxes.length * 72);
    final indices = Uint16List(boxes.length * 36);
    var v = 0, i = 0;
    for (final b in boxes) {
      for (var axis = 0; axis < 3; axis++) {
        final u = (axis + 1) % 3, w = (axis + 2) % 3;
        for (var side = 0; side < 2; side++) {
          final first = v;
          for (var k = 0; k < 4; k++) {
            // Corners (u, w) low-low, high-low, high-high, low-high turn
            // counter-clockwise seen from +axis: clockwise from the low face's
            // side as they are, from the high face's once reversed.
            final corner = side == 0 ? k : 3 - k;
            positions[v * 3 + axis] = side == 0 ? b.min[axis] : b.max[axis];
            positions[v * 3 + u] = corner == 1 || corner == 2 ? b.max[u] : b.min[u];
            positions[v * 3 + w] = corner >= 2 ? b.max[w] : b.min[w];
            normals[v * 3 + axis] = side == 0 ? -1.0 : 1.0;
            v++;
          }
          indices
            ..[i++] = first
            ..[i++] = first + 1
            ..[i++] = first + 2
            ..[i++] = first
            ..[i++] = first + 2
            ..[i++] = first + 3;
        }
      }
    }
    return (positions: positions, normals: normals, indices: indices);
  }

  /// [boxes] as one geometry, uploaded now (see [arrays]).
  static MeshGeometry geometry(List<Aabb3> boxes) {
    final a = arrays(boxes);
    return MeshGeometry.fromArrays(
      positions: a.positions,
      normals: a.normals,
      indices: a.indices,
      retainCpuData: false,
    );
  }
}
