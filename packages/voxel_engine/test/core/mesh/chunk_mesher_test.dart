import 'dart:math' as math;
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

  test('fences, ladders and rails keep their geometry (faces and a sum over every vertex)', () {
    final got = {for (final shape in _subShapes) shape.name: _fingerprint(shape)};
    expect(got, _subShapeFingerprints);
  });

  test('a result outlives the next build of its mesher, which meshes as a fresh one does', () {
    final mesher = _mesher();
    final hills = _hills();
    final first = mesher.build(0, 0, [hills, ...ChunkMesher.noNeighbours]).solid;
    final kept = [first.positions.toList(), first.colors.toList(), first.indices.toList()];
    final lone = Uint8List(ChunkSize.volume)..[ChunkSize.index(8, 40, 8)] = 1;
    final second = mesher.build(0, 0, [lone, ...ChunkMesher.noNeighbours]).solid;
    expect([first.positions, first.colors, first.indices], kept);
    expect(second.faceCount, 6);
    final again = mesher.build(0, 0, [hills, ...ChunkMesher.noNeighbours]).solid;
    final fresh = _build(hills).solid;
    expect(
      [again.positions, again.normals, again.colors, again.light, again.indices],
      [fresh.positions, fresh.normals, fresh.colors, fresh.light, fresh.indices],
    );
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

  test('two touching cubes cull the shared faces and merge the rest', () {
    final c = Uint8List(ChunkSize.volume)
      ..[ChunkSize.index(8, 40, 8)] = 1
      ..[ChunkSize.index(9, 40, 8)] = 1;
    final r = _build(c);
    expect(r.solid.faceCount, 6);
    // The top is one quad from x 8 to 10.
    final xs = [for (var v = 0; v < 4; v++) r.solid.positions[v * 3]];
    expect(xs.reduce(math.min), 8);
    expect(xs.reduce(math.max), 10);
  });

  test('a flat floor of one block is one quad on top and on each side', () {
    final c = Uint8List(ChunkSize.volume);
    for (var z = 0; z < ChunkSize.sizeZ; z++) {
      for (var x = 0; x < ChunkSize.sizeX; x++) {
        c[ChunkSize.index(x, 40, z)] = 1;
      }
    }
    final s = _build(c).solid;
    final perDirection = List<int>.filled(6, 0);
    for (var q = 0; q < s.faceCount; q++) {
      perDirection[_direction(s.normals, s.indices[q * 6] ~/ 4 * 4)]++;
    }
    // The underside sees sky that came in from the border, a level less a
    // block further in: its faces differ in light and stay apart.
    expect([perDirection[0], ...perDirection.sublist(2)], [1, 1, 1, 1, 1]);
    expect(perDirection[1], greaterThan(1));
  });

  test('merged quads cover exactly the exposed faces, and their colour never changes along a merged edge', () {
    final c = _hills();
    final r = _build(c);
    final s = r.solid;
    // Area per direction, against a count of the exposed unit faces.
    final area = List<double>.filled(6, 0);
    for (var q = 0; q < s.faceCount; q++) {
      final v0 = s.indices[q * 6] ~/ 4 * 4;
      final f = _direction(s.normals, v0);
      final p = [for (var i = 0; i < 4; i++) _vec(s.positions, v0 + i)];
      final e1 = [for (var a = 0; a < 3; a++) p[1][a] - p[0][a]], e2 = [for (var a = 0; a < 3; a++) p[3][a] - p[0][a]];
      area[f] += _length(e1) * _length(e2);
      // An edge longer than a block joins two corners of the same colour, or
      // the interpolation would smear AO over cells that did not have it.
      for (var i = 0; i < 4; i++) {
        final j = (i + 1) % 4;
        final d = [for (var a = 0; a < 3; a++) p[j][a] - p[i][a]];
        if (_length(d) <= 1.0) continue;
        for (var ch = 0; ch < 4; ch++) {
          expect(s.colors[(v0 + i) * 4 + ch], s.colors[(v0 + j) * 4 + ch], reason: 'quad $q edge $i-$j');
        }
      }
    }
    expect(area, _exposedFaces(c));
    expect(s.faceCount, lessThan(_exposedFaces(c).reduce((a, b) => a + b) ~/ 2));
  });

  test('faces under different light do not merge', () {
    // A floor with a roof over half of it: the covered half sees less sky.
    final c = Uint8List(ChunkSize.volume);
    for (var z = 0; z < ChunkSize.sizeZ; z++) {
      for (var x = 0; x < ChunkSize.sizeX; x++) {
        c[ChunkSize.index(x, 40, z)] = 1;
        if (x < 8) c[ChunkSize.index(x, 50, z)] = 1;
      }
    }
    final s = _build(c).solid;
    final tops = <double>{};
    for (var q = 0; q < s.faceCount; q++) {
      final v0 = s.indices[q * 6] ~/ 4 * 4;
      if (_direction(s.normals, v0) == 0 && s.positions[v0 * 3 + 1] == 41) tops.add(s.light[v0 * 2]);
    }
    expect(tops.length, greaterThan(1), reason: 'the open and the covered floor keep their own sky level');
  });

  test('a pool of water is one lowered top', () {
    final m = ChunkMesher(
      palette: Float32List.fromList([0, 0, 0, 0, 0.5, 0.5, 0.5, 1, 0.2, 0.4, 0.8, 0.6]),
      shape: Uint8List.fromList([BlockShape.cube.index, BlockShape.cube.index, BlockShape.liquid.index]),
      opaque: Uint8List.fromList([0, 1, 0]),
      emission: Uint8List.fromList([0, 0, 0]),
    );
    final c = Uint8List(ChunkSize.volume);
    for (var z = 0; z < ChunkSize.sizeZ; z++) {
      for (var x = 0; x < ChunkSize.sizeX; x++) {
        c[ChunkSize.index(x, 39, z)] = 1;
        c[ChunkSize.index(x, 40, z)] = 2;
        c[ChunkSize.index(x, 41, z)] = 2;
      }
    }
    final l = m.build(0, 0, [c, ...ChunkMesher.noNeighbours]).liquid;
    // The top, and each side as a full lower row plus a lowered upper row.
    expect(l.faceCount, 1 + 4 * 2);
    final ys = {for (var v = 0; v < l.vertexCount; v++) l.positions[v * 3 + 1]};
    expect(ys, {40.0, 41.0, 41.875});
  });

  test('voxelTint is 0.93..1.07 and only the glow surface bakes it', () {
    for (var i = -50; i < 50; i++) {
      final t = ChunkMesher.voxelTint(i * 7919, i, -i * 104729);
      expect(t, inInclusiveRange(0.93, 1.07));
    }
    final lamp = ChunkMesher(
      palette: Float32List.fromList([0, 0, 0, 0, 0.5, 0.5, 0.5, 1]),
      shape: Uint8List.fromList([BlockShape.cube.index, BlockShape.cube.index]),
      opaque: Uint8List.fromList([0, 1]),
      emission: Uint8List.fromList([0, 15]),
    );
    final c = Uint8List(ChunkSize.volume)..[ChunkSize.index(3, 40, 5)] = 1;
    final g = lamp.build(2, -1, [c, ...ChunkMesher.noNeighbours]).glow;
    expect(
      g.colors[0],
      closeTo(0.5 * ChunkMesher.voxelTint(2 * 16 + 3, 40, -16 + 5), 1e-6),
      reason: 'the top: tint 1, AO 3',
    );
    expect(_build(c).solid.colors[0], 0.5, reason: 'a lit face carries no variation');
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

/// The shapes drawn by [ChunkMesher]'s own methods rather than cube faces.
const _subShapes = [
  BlockShape.fence,
  BlockShape.ladder,
  BlockShape.railNs,
  BlockShape.railEw,
  BlockShape.railNe,
  BlockShape.railNw,
  BlockShape.railSe,
  BlockShape.railSw,
  BlockShape.railSlopeN,
  BlockShape.railSlopeE,
  BlockShape.railSlopeS,
  BlockShape.railSlopeW,
];

/// [_fingerprint] of each of [_subShapes], taken from the mesher before its
/// per-shape code left the cell loop (PF9): the move changed no vertex.
const Map<String, String> _subShapeFingerprints = {
  'fence': '74 61959.974',
  'ladder': '106 88417.631',
  'railNs': '74 61606.488',
  'railEw': '76 63245.083',
  'railNe': '100 83574.821',
  'railNw': '98 81657.503',
  'railSe': '100 83775.961',
  'railSw': '98 81872.237',
  'railSlopeN': '172 144811.021',
  'railSlopeE': '174 146416.459',
  'railSlopeS': '172 144839.010',
  'railSlopeW': '174 146379.118',
};

/// One [shape] block (id 2) on a floor of cubes (id 1), a cube beside it at
/// -x and a second [shape] block at +z (a fence joins both, a ladder hangs on
/// the cube): its solid surface's face count and a weighted sum over every
/// position, colour and light value.
String _fingerprint(BlockShape shape) {
  final mesher = ChunkMesher(
    palette: Float32List.fromList([0, 0, 0, 0, 0.5, 0.5, 0.5, 1, 0.6, 0.4, 0.2, 1]),
    shape: Uint8List.fromList([BlockShape.cube.index, BlockShape.cube.index, shape.index]),
    opaque: Uint8List.fromList([0, 1, 0]),
    emission: Uint8List.fromList([0, 0, 0]),
  );
  final c = Uint8List(ChunkSize.volume);
  for (var z = 4; z < 12; z++) {
    for (var x = 4; x < 12; x++) {
      c[ChunkSize.index(x, 39, z)] = 1;
    }
  }
  c[ChunkSize.index(7, 40, 8)] = 1;
  c[ChunkSize.index(8, 40, 8)] = 2;
  c[ChunkSize.index(8, 40, 9)] = 2;
  final s = mesher.build(0, 0, [c, ...ChunkMesher.noNeighbours]).solid;
  var sum = 0.0;
  for (final (weight, values) in [(1.0, s.positions), (3.0, s.colors), (7.0, s.light)]) {
    for (var i = 0; i < values.length; i++) {
      sum += values[i] * weight * (i % 5 + 1);
    }
  }
  return '${s.faceCount} ${sum.toStringAsFixed(3)}';
}

/// Terraced hills of block 1 with pits and overhangs: faces of every
/// direction, AO in every pattern.
Uint8List _hills() {
  final c = Uint8List(ChunkSize.volume);
  for (var z = 0; z < ChunkSize.sizeZ; z++) {
    for (var x = 0; x < ChunkSize.sizeX; x++) {
      final h = 40 + (3 * math.sin(x / 3) * math.cos(z / 4)).round();
      for (var y = 30; y < h; y++) {
        c[ChunkSize.index(x, y, z)] = 1;
      }
      if ((x * 7 + z * 3) % 11 == 0) c[ChunkSize.index(x, h + 2, z)] = 1;
      if ((x * 5 + z) % 13 == 0) c[ChunkSize.index(x, h - 1, z)] = 0;
    }
  }
  return c;
}

/// Exposed unit faces of block 1 per direction (+Y, -Y, +X, -X, +Z, -Z), air
/// past the chunk's border, none under y 0.
List<double> _exposedFaces(Uint8List c) {
  const d = [(0, 1, 0), (0, -1, 0), (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)];
  bool solid(int x, int y, int z) =>
      x >= 0 &&
      x < ChunkSize.sizeX &&
      z >= 0 &&
      z < ChunkSize.sizeZ &&
      y >= 0 &&
      y < ChunkSize.sizeY &&
      c[ChunkSize.index(x, y, z)] == 1;
  final n = List<double>.filled(6, 0);
  for (var y = 0; y < ChunkSize.sizeY; y++) {
    for (var z = 0; z < ChunkSize.sizeZ; z++) {
      for (var x = 0; x < ChunkSize.sizeX; x++) {
        if (!solid(x, y, z)) continue;
        for (final (f, (dx, dy, dz)) in d.indexed) {
          if (y + dy >= 0 && !solid(x + dx, y + dy, z + dz)) n[f]++;
        }
      }
    }
  }
  return n;
}

List<double> _vec(Float32List a, int v) => [a[v * 3], a[v * 3 + 1], a[v * 3 + 2]];

double _length(List<double> v) => math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

/// The face direction of vertex [v]'s normal, in the mesher's order.
int _direction(Float32List normals, int v) {
  final n = _vec(normals, v);
  if (n[1] != 0) return n[1] > 0 ? 0 : 1;
  if (n[0] != 0) return n[0] > 0 ? 2 : 3;
  return n[2] > 0 ? 4 : 5;
}
