import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

void main() {
  test('a crack stage holds its sticks and every earlier stage\'s, on the six faces', () {
    final stages = [for (var s = 0; s < 4; s++) FirstPersonView.crackBoxes(s)];
    // 2, 2, 3 and 3 segments a face, six faces.
    expect([for (final s in stages) s.length], [12, 24, 42, 60]);
    for (var s = 1; s < 4; s++) {
      for (var i = 0; i < stages[s - 1].length; i++) {
        expect(stages[s][i].min, stages[s - 1][i].min, reason: 'stage $s stick $i');
        expect(stages[s][i].max, stages[s - 1][i].max, reason: 'stage $s stick $i');
      }
    }
    final faces = <String>{};
    for (final b in stages.last) {
      final size = b.max - b.min;
      // Thin across its face, just off the cell, inside the face's square.
      final axis = [0, 1, 2].singleWhere((a) => (size[a] - 0.012).abs() < 1e-6);
      final c = b.center[axis];
      expect((c + 0.004).abs() < 1e-6 || (c - 1.004).abs() < 1e-6, isTrue, reason: '$b');
      faces.add('$axis:${c < 0.5}');
      for (final other in [(axis + 1) % 3, (axis + 2) % 3]) {
        expect(b.min[other], greaterThanOrEqualTo(0.0));
        expect(b.max[other], lessThanOrEqualTo(1.0));
      }
    }
    expect(faces, hasLength(6));
  });
}
