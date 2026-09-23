import 'dart:math' as math;
import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/core/species.dart';
import 'package:voxel_game_minecraft/src/entities/spawner.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 31's headless proofs (the app's `--stage31` covers the rest): the sky
/// and block light the mesher floods at known cells, the light riding the second
/// UV set instead of the colour, the AO diagonal, the spawn gate, and A* around
/// a wall, up a step and with no way through.
void main() {
  int id(String s) => Blocks.indexOf(s);
  const floorY = 10; // stone below, the walk floor at y 10

  ChunkMesher mesher({bool lighting = true}) => ChunkMesher(
      palette: Blocks.palette(), shape: Blocks.shapes(), opaque: Blocks.opaqueTable(), emission: Blocks.emission(), lighting: lighting);

  Uint8List floorChunk() {
    final c = Uint8List(VoxelWorld.volume);
    for (var i = 0; i < 16 * 16 * floorY; i++) {
      c[i] = id('stone');
    }
    return c;
  }

  void put(Uint8List c, int x, int y, int z, String block) => c[ChunkSize.index(x, y, z)] = id(block);
  int at(Uint8List v, int x, int y, int z) => v[ChunkSize.index(x, y, z)];
  ChunkMeshResult build(Uint8List c, {bool lighting = true}) =>
      mesher(lighting: lighting).build(0, 0, [c, ...ChunkMesher.noNeighbours]);

  /// A cave: stone from the floor up to y 20 everywhere, a 7x7x4 room carved at
  /// x/z 3..9, y 10..13, a wall torch on its north wall at (6, 11, 3).
  Uint8List cave({bool torch = true}) {
    final c = floorChunk();
    for (var y = floorY; y <= 20; y++) {
      for (var z = 0; z < 16; z++) {
        for (var x = 0; x < 16; x++) {
          final inside = x >= 3 && x <= 9 && z >= 3 && z <= 9 && y <= 13;
          if (!inside) put(c, x, y, z, 'stone');
        }
      }
    }
    if (torch) put(c, 6, 11, 3, 'wall_torch');
    return c;
  }

  test('a torch in a cave: block light 13 at the torch, -1 per step, no sky', () {
    expect(Blocks.lightOf(id('wall_torch')), 13);
    final r = build(cave());
    expect(at(r.block, 6, 11, 3), 13);
    expect(at(r.block, 6, 11, 6), 10); // three steps
    expect(at(r.block, 9, 13, 9), 2); // 3 + 2 + 6 steps
    expect(at(r.sky, 6, 11, 6), 0);
    expect(at(r.sky, 6, 21, 6), 15); // open sky over the rock
    final dark = build(cave(torch: false));
    expect(at(dark.block, 6, 11, 6), 0);
  });

  test('under an overhang: skylight spreads in from the open side at -1 a step', () {
    final c = floorChunk();
    for (var z = 0; z < 16; z++) {
      for (var x = 0; x < 8; x++) {
        put(c, x, 12, z, 'stone'); // a roof over x 0..7, open from x 8
      }
    }
    final r = build(c);
    expect(at(r.sky, 8, 10, 8), 15);
    expect(at(r.sky, 7, 11, 8), 14);
    // x 4: four steps from the open side (five from the padded air past x -1).
    expect(at(r.sky, 4, 10, 8), 11);
    // `--no-light`: skylight everywhere, no block light.
    final flat = build(cave(), lighting: false);
    expect(at(flat.sky, 6, 11, 6), 15);
    expect(at(flat.block, 6, 11, 3), 0);
  });

  test('the light rides the second UV set; the colour keeps tint x AO only', () {
    final r = build(cave());
    final s = r.solid;
    expect(s.light.length, s.vertexCount * 2);
    // The floor top of cell (6, 9, 6), lit from (6, 10, 6), four steps from the
    // torch: sky 0, block 9 / 15. Every quad adds 4 vertices, and a +Y face's
    // first vertex is its min corner.
    var found = false;
    for (var v = 0; v < s.vertexCount; v += 4) {
      final x = s.positions[v * 3], y = s.positions[v * 3 + 1], z = s.positions[v * 3 + 2];
      if (y == 10.0 && x == 6.0 && z == 6.0 && s.normals[v * 3 + 1] == 1.0) {
        expect(s.light[v * 2], 0.0);
        expect(s.light[v * 2 + 1], closeTo(9 / 15, 1e-6));
        // Unlit colour: stone x noise x face tint 1 x AO 1, whatever the dark says.
        expect(s.colors[v * 4], greaterThan(Blocks.palette()[id('stone') * 4] * 0.9));
        found = true;
      }
    }
    expect(found, isTrue);
    // A wall torch is full bright whatever its cell reads.
    final flame = r.solid;
    var bright = 0;
    for (var v = 0; v < flame.vertexCount; v++) {
      if (flame.light[v * 2] == 0.0 && flame.light[v * 2 + 1] == 1.0) bright++;
    }
    expect(bright, 24); // the six faces of the torch box
  });

  test("AO: the diagonal never runs through the darker corner, and quads wind clockwise (Godot's winding)", () {
    final c = floorChunk();
    put(c, 5, floorY, 5, 'stone'); // darkens one corner of the floor top at (6, 9, 6)
    final r = build(c);
    expect(r.aoVerts, greaterThan(0));
    final s = r.solid;
    Vector3 pos(int v) => Vector3(s.positions[v * 3], s.positions[v * 3 + 1], s.positions[v * 3 + 2]);
    var checked = 0;
    for (var q = 0; q < s.faceCount; q++) {
      final tri = [for (var k = 0; k < 6; k++) s.indices[q * 6 + k]];
      final first = tri.reduce(math.min);
      // Clockwise seen from the face's normal side (Godot's `Quad`).
      final n = Vector3(s.normals[first * 3], s.normals[first * 3 + 1], s.normals[first * 3 + 2]);
      for (var t = 0; t < 2; t++) {
        final a = pos(tri[t * 3]), b = pos(tri[t * 3 + 1]), cc = pos(tri[t * 3 + 2]);
        expect((b - a).cross(cc - a).dot(n), lessThan(0), reason: 'quad $q triangle $t');
      }
      final p0 = pos(first);
      if (n.y == 1.0 && p0.y == floorY.toDouble() && p0.x == 6.0 && p0.z == 6.0) {
        // Vertex 0 of this +Y face is the corner at (6, 10, 6) beside the lone block.
        final shared = tri.sublist(0, 3).toSet().intersection(tri.sublist(3).toSet());
        expect(shared.contains(first), isFalse, reason: 'the darker corner is off the shared diagonal');
        expect(s.colors[first * 4], lessThan(s.colors[(first + 1) * 4]));
        checked++;
      }
    }
    expect(checked, 1);
  });

  test('spawn gate: block + sky x day < 7; hostiles only where dark', () {
    expect(Spawner.lightAllowsHostile((sky: 15, block: 0), 1.0), isFalse); // noon field
    expect(Spawner.lightAllowsHostile((sky: 15, block: 0), 0.35), isTrue); // night field, 5.25
    expect(Spawner.lightAllowsHostile((sky: 7, block: 0), 1.0), isFalse); // 7 is not below 7
    expect(Spawner.lightAllowsHostile((sky: 6, block: 0), 1.0), isTrue); // a shaded pit by day
    expect(Spawner.lightAllowsHostile((sky: 0, block: 10), 0.0), isFalse); // a torch-lit cave
    final rng = math.Random(3);
    final lit = Species.candidates(2, true, false, false, rng);
    expect(lit.where((d) => d.hostile), isEmpty);
    expect(Species.candidates(2, true, false, true, rng).map((d) => d.id), contains('zombie'));
    expect(Species.candidates(2, false, true, true, rng).map((d) => d.id), contains('zombie')); // a dark cave by day
    // The world answers from the volumes a mesh job stored.
    final w = VoxelWorld(seedValue: 42, loadRadius: 1);
    expect(w.lightAt(const IVec3(6, 11, 6)), (sky: 15, block: 0)); // no mesh yet: open sky
    w.storeLight((x: 0, z: 0), build(cave()));
    expect(w.lightAt(const IVec3(6, 11, 6)), (sky: 0, block: 10));
  });

  group('A*', () {
    VoxelWorld flat(void Function(Uint8List c) carve) {
      final w = VoxelWorld(seedValue: 42, loadRadius: 1);
      final c = floorChunk();
      carve(c);
      w.chunks[(x: 0, z: 0)] = c;
      return w;
    }

    IVec3 cellOf(Vector3 v) => IVec3(v.x.floor(), v.y.floor(), v.z.floor());

    test('around a wall two blocks high', () {
      final w = flat((c) {
        for (var z = 2; z <= 12; z++) {
          put(c, 8, floorY, z, 'stone');
          put(c, 8, floorY + 1, z, 'stone');
        }
      });
      const from = IVec3(4, floorY, 7), to = IVec3(12, floorY, 7);
      final path = Pathfinder.find(w, from, to, costs: Blocks.pathCosts);
      expect(cellOf(path.last), to);
      expect(path.length, greaterThan(8)); // the straight line is 8
      for (final p in path) {
        expect(Pathfinder.walkable(w, cellOf(p), Blocks.pathCosts), isTrue);
        expect(p.x - p.x.floor(), 0.5);
      }
    });

    test('up a one-block step and down again', () {
      final w = flat((c) {
        for (var z = 0; z < 16; z++) {
          put(c, 6, floorY, z, 'stone');
        }
      });
      final path = Pathfinder.find(w, const IVec3(4, floorY, 7), const IVec3(8, floorY, 7), costs: Blocks.pathCosts);
      expect(path.map(cellOf), [
        const IVec3(5, floorY, 7),
        const IVec3(6, floorY + 1, 7),
        const IVec3(7, floorY, 7),
        const IVec3(8, floorY, 7),
      ]);
    });

    test('no path: the best partial path toward a walled-in goal', () {
      final w = flat((c) {
        for (var x = 10; x <= 14; x++) {
          for (var z = 10; z <= 14; z++) {
            if (x == 12 && z == 12) continue;
            put(c, x, floorY, z, 'stone');
            put(c, x, floorY + 1, z, 'stone');
          }
        }
      });
      const to = IVec3(12, floorY, 12);
      final path = Pathfinder.find(w, const IVec3(3, floorY, 3), to, costs: Blocks.pathCosts);
      expect(path, isNotEmpty);
      final last = cellOf(path.last);
      expect(last, isNot(to));
      expect((last.x - to.x).abs() + (last.z - to.z).abs(), 3); // the nearest cell outside the block of stone
    });
  });
}
