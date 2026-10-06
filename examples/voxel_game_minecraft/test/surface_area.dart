import 'package:voxel_engine/core.dart';

/// The area a surface of axis-aligned quads covers, in square blocks. It is what a
/// face count measured before voxel_engine 0.2.0-dev merged coplanar faces: the
/// merge changes how many quads there are, never how much they cover.
double surfaceArea(MeshSurface s) {
  var total = 0.0;
  for (var q = 0; q < s.vertexCount ~/ 4; q++) {
    final extent = [0.0, 0.0, 0.0];
    for (var axis = 0; axis < 3; axis++) {
      var lo = double.infinity, hi = double.negativeInfinity;
      for (var v = 0; v < 4; v++) {
        final p = s.positions[(q * 4 + v) * 3 + axis];
        if (p < lo) lo = p;
        if (p > hi) hi = p;
      }
      extent[axis] = hi - lo;
    }
    extent.sort();
    assert(extent[0] == 0, 'quad $q is not axis-aligned');
    total += extent[1] * extent[2];
  }
  return total;
}
