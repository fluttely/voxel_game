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

/// [parts] packed one by one and merged at their offsets, as `VoxelChunkView` does.
PackedSurface? _pack(List<(ChunkPos, MeshSurface)> parts) => PackedSurface.merge([
  for (final (offset, s) in parts)
    if (PackedSurface.of(s) case final packed?) (offset, packed),
]);

/// PF13's first packer (`7a5dcf6`), which packed a region's floats already moved
/// by their offsets: packing a chunk once and merging it must land on its bits.
({Uint32List positions, Uint32List attributes, List<int> indices, double minY, double maxY}) _packMoved(
  List<(ChunkPos, MeshSurface)> parts,
) {
  var vertices = 0, indexCount = 0;
  for (final (_, s) in parts) {
    vertices += s.vertexCount;
    indexCount += s.indices.length;
  }
  final positions = Uint32List(vertices * 2), attributes = Uint32List(vertices * 2);
  final List<int> indices = vertices <= 0x10000 ? Uint16List(indexCount) : Uint32List(indexCount);
  int fixed(double m) => (m * 256).round();
  int sqrtUnorm8(double x) => (math.sqrt(x) * 255).round();
  int snorm8(double x) => (x * 127).round() + 128;
  int level(double x) => (x * 15).round();
  var minY = double.infinity, maxY = double.negativeInfinity;
  var v = 0, k = 0;
  for (final (offset, s) in parts) {
    final ox = offset.x * ChunkSize.sizeX, oz = offset.z * ChunkSize.sizeZ;
    final p = s.positions, n = s.normals, c = s.colors, l = s.light;
    for (var j = 0; j < s.vertexCount; j++) {
      final y = p[j * 3 + 1];
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      positions[(v + j) * 2] = fixed(p[j * 3] + ox) | fixed(p[j * 3 + 2] + oz) << 16;
      positions[(v + j) * 2 + 1] = fixed(y);
      attributes[(v + j) * 2] =
          sqrtUnorm8(c[j * 4]) |
          sqrtUnorm8(c[j * 4 + 1]) << 8 |
          sqrtUnorm8(c[j * 4 + 2]) << 16 |
          (c[j * 4 + 3] * 255).round() << 24;
      attributes[(v + j) * 2 + 1] =
          snorm8(n[j * 3]) |
          snorm8(n[j * 3 + 1]) << 8 |
          snorm8(n[j * 3 + 2]) << 16 |
          level(l[j * 2]) << 24 |
          level(l[j * 2 + 1]) << 28;
    }
    for (final i in s.indices) {
      indices[k++] = i + v;
    }
    v += s.vertexCount;
  }
  return (positions: positions, attributes: attributes, indices: indices, minY: minY, maxY: maxY);
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
    final m = _pack([((x: 0, z: 0), quad(3)), ((x: 0, z: 1), empty), ((x: 1, z: 1), quad(7))])!;
    expect(m.vertexCount, 8);
    expect(m.positions, hasLength(16));
    expect(m.attributes, hasLength(16));
    expect(_unpack(m, 5).position, [17.0, 7.0, 16.0], reason: 'the second quad sits one chunk over on x and z');
    expect(m.indices, [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7]);
    expect(m.indices, isA<Uint16List>());
    expect(m.minY, 3.0);
    expect(m.maxY, closeTo(7.55, 1e-6));
    expect(PackedSurface.of(empty), isNull);
    expect(PackedSurface.merge([]), isNull);
  });

  test('the shader reads back what the mesher wrote, within the packing steps', () {
    final source = quad(127, sky: 11 / 15, block: 4 / 15);
    final m = _pack([((x: 2, z: 3), source)])!;
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
      Float32List.fromList([
        for (var i = 0; i < n; i++) ...[0.0, 1.0, 0.0],
      ]),
      Float32List(n * 4),
      Float32List(n * 2),
      Int32List.fromList([0, 1, 2, n - 3, n - 2, n - 1]),
    );
    final m = PackedSurface.of(big)!;
    expect(m.indices, isA<Uint32List>());
    expect(m.indices.last, n - 1);
    final small = PackedSurface.of(quad(1))!;
    final merged = PackedSurface.merge([((x: 0, z: 0), small), ((x: 1, z: 0), m)])!;
    expect(merged.indices, isA<Uint32List>(), reason: 'the merge counts every part\'s vertices');
    expect(merged.indices.last, n + 3);
  });

  test('packing each chunk once and merging lands on the bits of packing the region moved', () {
    final random = math.Random(13);
    // Positions on the mesher's grid (whole metres, the 1/16 steps of slabs and plants)
    // and off it, where rounding to 1/256 m has to agree on either path.
    double coordinate(int size) => switch (random.nextInt(3)) {
      0 => random.nextInt(size + 1).toDouble(),
      1 => random.nextInt(size * 16 + 1) / 16,
      _ => random.nextDouble() * size,
    };
    MeshSurface chunk(int faces) {
      final n = faces * 4;
      const axes = [
        [1.0, 0.0, 0.0],
        [-1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, -1.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 0.0, -1.0],
        [0.7071068, 0.0, 0.7071068],
        [-0.7071068, 0.0, -0.7071068],
      ];
      return MeshSurface(
        Float32List.fromList([
          for (var i = 0; i < n; i++) ...[
            coordinate(ChunkSize.sizeX),
            coordinate(ChunkSize.sizeY),
            coordinate(ChunkSize.sizeZ),
          ],
        ]),
        Float32List.fromList([for (var i = 0; i < n; i++) ...axes[random.nextInt(axes.length)]]),
        Float32List.fromList([for (var i = 0; i < n * 4; i++) random.nextDouble()]),
        Float32List.fromList([for (var i = 0; i < n * 2; i++) random.nextInt(16) / 15]),
        Int32List.fromList([
          for (var f = 0; f < faces; f++) ...[f * 4, f * 4 + 1, f * 4 + 2, f * 4, f * 4 + 2, f * 4 + 3],
        ]),
      );
    }

    for (final regionChunks in [1, 2, 4, 15]) {
      final parts = [
        for (var dx = 0; dx < regionChunks; dx++)
          for (var dz = 0; dz < regionChunks; dz++)
            if (random.nextInt(4) != 0) ((x: dx, z: dz), chunk(random.nextInt(3) == 0 ? 0 : 1 + random.nextInt(200))),
      ];
      final expected = _packMoved(parts);
      final m = _pack(parts);
      if (expected.positions.isEmpty) {
        expect(m, isNull);
        continue;
      }
      expect(m!.positions, expected.positions, reason: 'positions, $regionChunks chunks a side');
      expect(m.attributes, expected.attributes, reason: 'attributes, $regionChunks chunks a side');
      expect(m.indices, expected.indices, reason: 'indices, $regionChunks chunks a side');
      expect(m.indices.runtimeType, expected.indices.runtimeType);
      expect(m.minY, expected.minY);
      expect(m.maxY, expected.maxY);
    }
  });

  test('a merge fed one member at a time lands on merge word for word, and takes what it counted', () {
    final random = math.Random(29);
    MeshSurface chunk(int faces) => MeshSurface(
      Float32List.fromList([for (var i = 0; i < faces * 12; i++) random.nextInt(17).toDouble()]),
      Float32List.fromList([
        for (var i = 0; i < faces * 4; i++) ...[0.0, 1.0, 0.0],
      ]),
      Float32List.fromList([for (var i = 0; i < faces * 16; i++) random.nextDouble()]),
      Float32List.fromList([for (var i = 0; i < faces * 8; i++) random.nextInt(16) / 15]),
      Int32List.fromList([
        for (var f = 0; f < faces; f++) ...[f * 4, f * 4 + 1, f * 4 + 2, f * 4, f * 4 + 2, f * 4 + 3],
      ]),
    );
    final members = [
      for (var dx = 0; dx < 4; dx++)
        for (var dz = 0; dz < 4; dz++) ((x: dx, z: dz), PackedSurface.of(chunk(1 + random.nextInt(60)))!),
    ];
    final vertices = members.fold(0, (n, m) => n + m.$2.vertexCount);
    final indices = members.fold(0, (n, m) => n + m.$2.indices.length);
    final merge = PackedSurfaceMerge(vertices, indices);
    for (final (offset, s) in members.take(15)) {
      merge.add(offset, s);
    }
    expect(merge.finish, throwsStateError, reason: 'one member is still to come');
    merge.add(members.last.$1, members.last.$2);
    final fed = merge.finish();
    final whole = PackedSurface.merge(members)!;
    expect(fed.positions, whole.positions);
    expect(fed.attributes, whole.attributes);
    expect(fed.indices, whole.indices);
    expect(fed.indices.runtimeType, whole.indices.runtimeType);
    expect((fed.minY, fed.maxY), (whole.minY, whole.maxY));
    expect(() => merge.add(members.first.$1, members.first.$2), throwsStateError, reason: 'nothing past the count');
  });

  group('split', () {
    /// A packed surface of [n] vertices, each at the chunk's corner.
    PackedSurface sized(int n) => PackedSurface.of(
      MeshSurface(
        Float32List(n * 3),
        Float32List.fromList([
          for (var i = 0; i < n; i++) ...[0.0, 1.0, 0.0],
        ]),
        Float32List(n * 4),
        Float32List(n * 2),
        Int32List.fromList([0, 1, 2, n - 3, n - 2, n - 1]),
      ),
    )!;
    List<(ChunkPos, PackedSurface)> members(List<int> sizes) => [
      for (var i = 0; i < sizes.length; i++) ((x: i % 4, z: i ~/ 4), sized(sizes[i])),
    ];
    List<int> vertices(List<List<(ChunkPos, PackedSurface)>> parts) => [
      for (final part in parts) part.fold(0, (n, m) => n + m.$2.vertexCount),
    ];

    test('a part never passes 65,536 vertices and keeps 16-bit indices; one that needs three gets three', () {
      final parts = PackedSurface.split(members([30000, 30000, 30000, 30000, 30000]));
      expect(vertices(parts), [60000, 60000, 30000]);
      for (final part in parts) {
        final m = PackedSurface.merge(part)!;
        expect(m.vertexCount, lessThanOrEqualTo(PackedSurface.maxPartVertices));
        expect(m.indices, isA<Uint16List>());
      }
      expect(vertices(PackedSurface.split(members([40000, 40000, 40000, 20000, 10000]))), [40000, 40000, 60000, 10000]);
    });

    test('a part fills to exactly 65,536 vertices; a chunk over it alone is a part of its own, 32-bit', () {
      final full = PackedSurface.split(members([32768, 32768]));
      expect(vertices(full), [65536]);
      expect(PackedSurface.merge(full.single)!.indices, isA<Uint16List>(), reason: '65,536 vertices index 0..65535');
      final over = PackedSurface.split(members([100, 70000, 100]));
      expect(vertices(over), [100, 70000, 100]);
      expect(PackedSurface.merge(over[1])!.indices, isA<Uint32List>());
      expect(PackedSurface.split([]), isEmpty);
    });
  });

  test('a vertex outside its chunk fails', () {
    final far = MeshSurface(
      Float32List.fromList([ChunkSize.sizeX + 1, 0, 0]),
      Float32List.fromList([0, 1, 0]),
      Float32List.fromList([1, 1, 1, 1]),
      Float32List.fromList([1, 0]),
      Int32List(0),
    );
    expect(() => PackedSurface.of(far), throwsA(isA<AssertionError>()));
  });
}
