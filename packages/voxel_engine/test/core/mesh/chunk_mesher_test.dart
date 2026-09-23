import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

/// Air (0) and one opaque grey cube (1): the smallest table the mesher accepts.
ChunkMesher _mesher() => ChunkMesher(
      palette: Float32List.fromList([0, 0, 0, 0, 0.5, 0.5, 0.5, 1]),
      shape: Uint8List.fromList([BlockShape.cube.index, BlockShape.cube.index]),
      opaque: Uint8List.fromList([0, 1]),
      emission: Uint8List.fromList([0, 0]),
    );

ChunkMeshResult _build(Uint8List c) => _mesher().build(0, 0, [c, ...ChunkMesher.noNeighbours]);

void main() {
  test('the mesher shape ints are BlockShape indices (kept const for the hot loop)', () {
    expect(ChunkMesher.shapeIndices, [for (final s in BlockShape.values) s.index]);
  });

  test('build takes a ring of nine with the chunk first', () {
    final c = Uint8List(ChunkSize.volume);
    expect(() => _mesher().build(0, 0, [c]), throwsArgumentError);
    expect(() => _mesher().build(0, 0, [null, ...ChunkMesher.noNeighbours]), throwsArgumentError);
  });

  test('a lone cube in air meshes six faces; its top sees open sky, its bottom the sideways spread', () {
    final c = Uint8List(ChunkSize.volume)..[ChunkSize.index(8, 40, 8)] = 1;
    final r = _build(c);
    expect(r.solid.faceCount, 6);
    expect(r.solid.vertexCount, 24);
    expect(r.liquid.isEmpty && r.cutout.isEmpty && r.glow.isEmpty, isTrue);
    expect(r.aoVerts, 0);
    // Faces are emitted +Y, -Y, +X, -X, +Z, -Z, four vertices each; light is
    // (sky / 15, block / 15) of the cell the face looks into.
    for (var v = 0; v < 4; v++) {
      expect(r.solid.light[v * 2], 1.0, reason: 'top vertex $v');
    }
    // The cube shades the cell under it; skylight arrives from the side at -1.
    for (var v = 4; v < 8; v++) {
      expect(r.solid.light[v * 2], closeTo(14 / 15, 1e-6), reason: 'bottom vertex $v');
    }
  });

  test('two touching cubes cull the shared faces', () {
    final c = Uint8List(ChunkSize.volume)
      ..[ChunkSize.index(8, 40, 8)] = 1
      ..[ChunkSize.index(9, 40, 8)] = 1;
    expect(_build(c).solid.faceCount, 10);
  });

  test('a cube on the floor of the volume has no bottom face; its neighbours darken its AO', () {
    final c = Uint8List(ChunkSize.volume)..[ChunkSize.index(8, 0, 8)] = 1;
    expect(_build(c).solid.faceCount, 5);
    final pit = Uint8List(ChunkSize.volume)
      ..[ChunkSize.index(8, 40, 8)] = 1
      ..[ChunkSize.index(7, 41, 8)] = 1;
    expect(_build(pit).aoVerts, greaterThan(0));
  });

  test('the light volumes are chunk-sized and read 15 sky above the terrain', () {
    final r = _build(Uint8List(ChunkSize.volume));
    expect(r.sky, hasLength(ChunkSize.volume));
    expect(r.block, hasLength(ChunkSize.volume));
    expect(r.sky[ChunkSize.index(0, 127, 0)], 15);
    expect(r.faces, 0);
  });
}
