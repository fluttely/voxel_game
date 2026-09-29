import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

/// The sign of each triangle's winding against its vertex normal: +1 when
/// counter-clockwise seen from the normal side, -1 when clockwise.
List<double> windings(List<double> positions, List<double> normals, List<int> indices) {
  Vector3 at(List<double> a, int v) => Vector3(a[v * 3], a[v * 3 + 1], a[v * 3 + 2]);
  return [
    for (var i = 0; i < indices.length; i += 3)
      ((at(positions, indices[i + 1]) - at(positions, indices[i])).cross(
        at(positions, indices[i + 2]) - at(positions, indices[i]),
      )).dot(at(normals, indices[i])).sign,
  ];
}

void main() {
  final boxes = [
    Aabb3.minMax(Vector3(0, 0, 0), Vector3(1, 1, 1)),
    Aabb3.minMax(Vector3(-0.5, 2, 0.25), Vector3(0.5, 2.03, 3)),
  ];

  test('six faces a box, four vertices and six indices a face', () {
    final a = BoxMesh.arrays(boxes);
    expect(a.positions, hasLength(2 * 6 * 4 * 3));
    expect(a.normals, hasLength(2 * 6 * 4 * 3));
    expect(a.indices, hasLength(2 * 6 * 6));
    expect(a.indices.reduce((x, y) => x > y ? x : y), 2 * 6 * 4 - 1);
  });

  test('every face lies on its box, its normal pointing out', () {
    final a = BoxMesh.arrays(boxes);
    for (var v = 0; v < a.positions.length ~/ 3; v++) {
      final b = boxes[v ~/ 24];
      final p = Vector3(a.positions[v * 3], a.positions[v * 3 + 1], a.positions[v * 3 + 2]);
      final n = Vector3(a.normals[v * 3], a.normals[v * 3 + 1], a.normals[v * 3 + 2]);
      expect(n.length, 1.0);
      expect(b.intersectsWithVector3(p), isTrue, reason: 'vertex $v at $p');
      final axis = n.x != 0 ? 0 : (n.y != 0 ? 1 : 2);
      expect(p[axis], n[axis] < 0 ? b.min[axis] : b.max[axis], reason: 'vertex $v');
    }
  });

  test('every triangle winds as a voxel model does, the chunk mesher\'s way', () {
    final a = BoxMesh.arrays(boxes);
    final model = VoxelModel.arrays({const IVec3(0, 0, 0): Vector3.all(1)}, 1.0)!;
    final modelWinding = windings(model.positions, model.normals, model.indices).toSet();
    expect(modelWinding, hasLength(1));
    expect(windings(a.positions, a.normals, a.indices).toSet(), modelWinding);
  });
}
