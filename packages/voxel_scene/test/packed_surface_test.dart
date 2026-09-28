import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/src/packed_surface.dart';

/// What `shaders/terrain.vert` makes of vertex [i]: position, normal, linear
/// colour and the two light levels / 15, decoded as the shader does.
({List<double> position, List<double> normal, List<double> color, List<double> light}) _unpack(PackedSurface m, int i) {
  final p0 = m.positions[i * 2], p1 = m.positions[i * 2 + 1];
  final c = m.attributes[i * 2], w = m.attributes[i * 2 + 1];
  double biased(int shift) => (((w >> shift) & 0xFF) - 128) / 127;
  double squared(int shift) => ((c >> shift) & 0xFF) / 255 * (((c >> shift) & 0xFF) / 255);
  return (
    position: [(p0 & 0xFFFF) / 256, (p1 & 0xFFFF) / 256, (p0 >> 16) / 256],
    normal: [biased(0), biased(8), biased(16)],
    color: [squared(0), squared(8), squared(16), (c >> 24) / 255],
    light: [((w >> 24) & 0xF) / 15, (w >> 28) / 15],
  );
}

void main() {
  MeshSurface quad(double y, {double sky = 1.0, double block = 0.0}) => MeshSurface(
    Float32List.fromList([0, y, 0, 1, y, 0, 1, y, 1, 0.28, y + 0.55, 0.9]),
    Float32List.fromList([0, 1, 0, 0, -1, 0, 0.7, 0, -0.7, -0.7, 0, 0.7]),
    Float32List.fromList([1, 0.5, 0.02, 1, 0, 0, 0, 0.62, 0.3, 0.3, 0.3, 1, 0.8, 0.7, 0.6, 0.5]),
    Float32List.fromList([sky, block, sky, block, sky, block, sky, block]),
    Int32List.fromList([0, 1, 2, 0, 2, 3]),
  );
  final empty = MeshSurface(Float32List(0), Float32List(0), Float32List(0), Float32List(0), Int32List(0));

  test('a packed surface moves each chunk by its offset and its indices by the vertices before it', () {
    final m = PackedSurface.of([((x: 0, z: 0), quad(3)), ((x: 0, z: 1), empty), ((x: 1, z: 1), quad(7))])!;
    expect(m.vertexCount, 8);
    expect(m.positions, hasLength(16));
    expect(m.attributes, hasLength(16));
    expect(_unpack(m, 5).position, [17.0, 7.0, 16.0], reason: 'the second quad sits one chunk over on x and z');
    expect(m.indices, [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7]);
    expect(m.indices, isA<Uint16List>());
    expect(m.minY, 3.0);
    expect(m.maxY, closeTo(7.55, 1e-6));
    expect(PackedSurface.of([((x: 0, z: 0), empty)]), isNull);
  });

  test('the shader reads back what the mesher wrote, within the packing steps', () {
    final source = quad(127, sky: 11 / 15, block: 4 / 15);
    final m = PackedSurface.of([((x: 2, z: 3), source)])!;
    for (var i = 0; i < 4; i++) {
      final v = _unpack(m, i);
      final at = [source.positions[i * 3] + 32, source.positions[i * 3 + 1], source.positions[i * 3 + 2] + 48];
      for (var k = 0; k < 3; k++) {
        expect(v.position[k], closeTo(at[k], 0.5 / 256), reason: 'vertex $i position $k');
        expect(v.normal[k], closeTo(source.normals[i * 3 + k], 0.5 / 127), reason: 'vertex $i normal $k');
      }
      for (var k = 0; k < 4; k++) {
        final linear = source.colors[i * 4 + k];
        // Stored as its square root, a channel is off by at most sqrt(c) / 255: 3% of a
        // channel at 0.02, where 8 linear bits would lose 10%.
        final step = k < 3 ? math.sqrt(linear) / 255 + 1 / (255 * 255) : 0.5 / 255;
        expect(v.color[k], closeTo(linear, step), reason: 'vertex $i colour $k');
      }
      expect(v.light, [11 / 15, 4 / 15]);
    }
    expect(_unpack(m, 0).position, [32.0, 127.0, 48.0], reason: 'a whole metre is exact');
  });

  test('more than 65536 vertices take 32-bit indices', () {
    final n = 0x10000 + 4;
    final big = MeshSurface(
      Float32List(n * 3),
      Float32List.fromList([for (var i = 0; i < n; i++) ...[0.0, 1.0, 0.0]]),
      Float32List(n * 4),
      Float32List(n * 2),
      Int32List.fromList([0, 1, 2, n - 3, n - 2, n - 1]),
    );
    final m = PackedSurface.of([((x: 0, z: 0), big)])!;
    expect(m.indices, isA<Uint32List>());
    expect(m.indices.last, n - 1);
  });

  test('a vertex outside the 256 m a packed position spans fails', () {
    final far = MeshSurface(
      Float32List.fromList([256, 0, 0]),
      Float32List.fromList([0, 1, 0]),
      Float32List.fromList([1, 1, 1, 1]),
      Float32List.fromList([1, 0]),
      Int32List(0),
    );
    expect(() => PackedSurface.of([((x: 0, z: 0), far)]), throwsA(isA<AssertionError>()));
  });
}
