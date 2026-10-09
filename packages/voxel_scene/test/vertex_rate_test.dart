import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_scene/src/vertex_rate.dart';

void main() {
  test('no sample is no cost; one sample is its own rate', () {
    final rate = VertexRate();
    expect(rate.usPerVertex, 0.0);
    rate.add(170, 60432);
    expect(rate.usPerVertex, closeTo(170 / 60432, 1e-12));
  });

  test('a small part\'s fixed cost does not price a large part over the budget', () {
    // Uploads measured on the Mac (profile) as one 4 x 4 settled: the 128-vertex
    // part costs 133 ns a vertex, the 60,432-vertex one 2.8.
    final rate = VertexRate()
      ..add(170, 60432)
      ..add(81, 22200)
      ..add(59, 1872)
      ..add(17, 128);
    expect(rate.usPerVertex * 65536, lessThan(500), reason: 'a full part, priced near what it cost');
    for (var i = 0; i < 10; i++) {
      rate.add(17, 128);
    }
    expect(rate.usPerVertex * 65536, lessThan(2000), reason: 'even after ten small parts in a row');
  });

  test('older samples fade', () {
    final rate = VertexRate(fade: 0.5)..add(1000, 1000);
    for (var i = 0; i < 20; i++) {
      rate.add(2000, 1000);
    }
    expect(rate.usPerVertex, closeTo(2.0, 1e-3));
    expect(() => rate.add(1, 0), throwsArgumentError);
  });
}
