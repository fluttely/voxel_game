import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

void main() {
  test('a lone voxel has six faces; two touching voxels hide the shared pair', () {
    final one = <IVec3, Vector3>{IVec3.zero: Vector3(1, 0, 0)};
    expect(VoxelModel.arrays(one, 0.1)!.faces, 6);
    final two = {...one, const IVec3(1, 0, 0): Vector3(0, 1, 0)};
    final a = VoxelModel.arrays(two, 0.1)!;
    expect(a.faces, 10);
    expect(a.positions.length, 10 * 12);
    expect(a.indices.length, 10 * 6);
    expect(VoxelModel.arrays(<IVec3, Vector3>{}, 0.1), isNull);
  });

  test('scale and origin place the mesh; each face carries its tint', () {
    final a = VoxelModel.arrays({IVec3.zero: Vector3(1, 1, 1)}, 0.5, Vector3(0.5, 0, 0.5))!;
    var lo = double.infinity, hi = double.negativeInfinity;
    for (var i = 0; i < a.positions.length; i += 3) {
      lo = math.min(lo, a.positions[i]);
      hi = math.max(hi, a.positions[i]);
    }
    expect(lo, closeTo(-0.25, 1e-6));
    expect(hi, closeTo(0.25, 1e-6));
    expect(a.colors[0], closeTo(VoxelModel.faceTint[0], 1e-6), reason: 'the top face comes first');
    expect(a.colors[16], closeTo(VoxelModel.faceTint[1], 1e-6));
  });

  test('box fills inclusive; mirrorX maps x to -x-1', () {
    final v = <IVec3, Vector3>{};
    VoxelModel.box(v, IVec3.zero, const IVec3(1, 2, 0), Vector3(0.5, 0.5, 0.5), 0.0);
    expect(v, hasLength(6));
    expect(v[const IVec3(1, 2, 0)], Vector3(0.5, 0.5, 0.5));
    final m = VoxelModel.mirrorX(v);
    expect(m.keys.map((p) => p.x).toSet(), {-1, -2});
  });

  test('angles: the short way round, and Y-X-Z order', () {
    expect(lerpAngle(3.0, -3.0, 0.5), closeTo(math.pi, 0.01));
    expect(lerpd(2, 4, 0.25), 2.5);
    final y = Quaternion.axisAngle(Vector3(0, 1, 0), 0.7), x = Quaternion.axisAngle(Vector3(1, 0, 0), 0.3);
    final z = Quaternion.axisAngle(Vector3(0, 0, 1), -0.2);
    final q = eulerYXZ(0.3, 0.7, -0.2), expected = y * x * z;
    for (var i = 0; i < 4; i++) {
      expect(q.storage[i], closeTo(expected.storage[i], 1e-6));
    }
  });
}
