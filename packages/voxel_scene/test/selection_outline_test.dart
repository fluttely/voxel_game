import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test('the twelve sticks trace the box edges, gap off and corner to corner', () {
    const box = CollisionBox(2, 3, 4, 3, 3.5, 5); // a slab: 1 x 0.5 x 1
    final sticks = SelectionOutline.stickTransforms(box);
    expect(sticks, hasLength(12));
    const g = SelectionOutline.gap, t = SelectionOutline.thickness;
    final span = Vector3(1, 0.5, 1);
    for (var axis = 0; axis < 3; axis++) {
      final corners = <String>{};
      for (var corner = 0; corner < 4; corner++) {
        final s = sticks[axis * 4 + corner];
        // Centred along its own axis, stretched past both ends to close the joints.
        expect(s.position[axis], closeTo(span[axis] / 2, 1e-6));
        expect(s.scale[axis], closeTo(span[axis] + 2 * g + t, 1e-6));
        for (final other in [(axis + 1) % 3, (axis + 2) % 3]) {
          expect(s.scale[other], 1.0);
          final p = s.position[other];
          expect(
            (p + g).abs() < 1e-6 || (p - (span[other] + g)).abs() < 1e-6,
            isTrue,
            reason: 'axis $axis corner $corner',
          );
        }
        corners.add('${s.position[(axis + 1) % 3]},${s.position[(axis + 2) % 3]}');
      }
      expect(corners, hasLength(4), reason: 'the four edges along axis $axis are distinct');
    }
  });

  test('the depth bias clears a half-buried stick but not a whole block', () {
    expect(SelectionOutline.depthBias, greaterThan(4 * (SelectionOutline.thickness / 2 - SelectionOutline.gap)));
    expect(SelectionOutline.depthBias, lessThan(0.1));
  });
}
