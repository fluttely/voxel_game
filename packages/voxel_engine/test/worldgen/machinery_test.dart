import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/worldgen.dart';

const int _log = 1, _leaves = 2, _stone = 3, _ore = 4, _deepOre = 5;

Uint8List _chunk() => Uint8List(ChunkSize.volume);

void main() {
  group('worldHash', () {
    test('is pure in seed and position, and salts apart', () {
      expect(worldHash(42, 1, 2, 3), worldHash(42, 1, 2, 3));
      expect(worldHash(42, 1, 2, 3), isNot(worldHash(43, 1, 2, 3)));
      expect(worldHash(42, 1, 91, 3), isNot(worldHash(42, 1, 92, 3)));
      expect(worldHash(42, -5, 0, -7), inInclusiveRange(0, 0xFFFFFFFF));
    });

    test('floorDiv rounds toward negative infinity', () {
      expect(floorDiv(-1, 16), -1);
      expect(floorDiv(15, 16), 0);
      expect(floorDiv(-16, 16), -1);
      expect(floorDiv(-17, 16), -2);
    });
  });

  group('ChunkWriter', () {
    test('writes only inside its chunk and never row 0', () {
      final w = ChunkWriter(_chunk(), 1, -1); // world x 16..31, z -16..-1
      w.put(16, 5, -16, _stone);
      w.put(15, 5, -16, _stone); // the neighbour's
      w.put(20, 0, -5, _stone); // bedrock row
      expect(w.get(16, 5, -16), _stone);
      expect(w.get(15, 5, -16), isNull);
      expect(w.blocks.where((b) => b != 0), hasLength(1));
    });

    test('place keeps what is there unless it gives way', () {
      final w = ChunkWriter(_chunk(), 0, 0);
      w.place(1, 1, 1, _leaves);
      w.place(1, 1, 1, _stone);
      expect(w.get(1, 1, 1), _leaves, reason: 'a block is not drawn over another');
      w.place(1, 1, 1, _log, over: (b) => b == _leaves);
      expect(w.get(1, 1, 1), _log, reason: 'a trunk overwrites a canopy');
      w.place(1, 1, 1, 0);
      expect(w.get(1, 1, 1), 0, reason: 'air always clears');
    });

    test('levelColumn fills to the floor and clears above it', () {
      final w = ChunkWriter(_chunk(), 0, 0);
      for (var y = 1; y < 20; y++) {
        w.put(3, y, 3, _stone);
      }
      w.levelColumn(3, 3, 20, 25, 30, _log); // ground 20: fill 19..24, clear 26..30
      expect(w.get(3, 19, 3), _log);
      expect(w.get(3, 24, 3), _log);
      expect(w.get(3, 18, 3), _stone);
      w.levelColumn(3, 3, 20, 10, 30, _log); // a floor under the ground: clear it
      expect(w.get(3, 15, 3), 0);
      expect(w.get(3, 10, 3), _stone);
    });
  });

  test('ScatterGrid: one spot per patch, inset from its border, the same from any column', () {
    const grid = ScatterGrid(patch: 7, inset: 2, salt: 91);
    final seen = <(int, int)>{};
    for (var x = -21; x < 21; x++) {
      for (var z = -21; z < 21; z++) {
        final s = grid.spotOf(9, x, z);
        expect(grid.spotOf(9, s.x, s.z), s, reason: 'the spot of a spot is itself');
        expect(floorDiv(s.x, 7), floorDiv(x, 7));
        expect(s.x - floorDiv(x, 7) * 7, inInclusiveRange(2, 4));
        seen.add((s.x, s.z));
      }
    }
    expect(seen, hasLength(36));
  });

  test('StructureGrid: 3 x 3 regions around a chunk, hashed per region', () {
    const grid = StructureGrid(regionChunks: 6, primeX: 7919, salt: 11, primeZ: 104729);
    expect(grid.span, 96);
    expect(grid.regionOf(-1), -1);
    final around = grid.around(5, -7).toList();
    expect(around, hasLength(9));
    expect(around.first, (-1, -3));
    expect(around.last, (1, -1));
    expect(grid.hashOf(42, 0, 0), worldHash(42, 0, 11, 0));
  });

  test('OreTable: first vein by depth and cumulative roll, thinned by fill', () {
    const table = OreTable([OreVein(_deepOre, belowY: 20, upTo: 100), OreVein(_ore, upTo: 1000)]);
    expect(table.pick(10, 50, 0), _deepOre);
    expect(table.pick(30, 50, 0), _ore, reason: 'too high for the deep ore, inside the common one');
    expect(table.pick(10, 500, 0), _ore);
    expect(table.pick(10, 5000, 0), isNull);
    expect(table.pick(10, 50, 55), isNull, reason: 'thinned: 55 is not under the 55 per cent fill');
  });

  test('CaveCarver: never carves the top blocks without a mouth, is pure', () {
    final carver = CaveCarver(cave: simplexNoise(1, 0.05, 2), cavern: simplexNoise(2, 0.02, 2), seaLevel: 46);
    var carved = 0;
    for (var x = 0; x < 64; x++) {
      for (var y = 5; y < 60; y++) {
        final a = carver.carved(x, y, 7, 64);
        expect(a, carver.carved(x, y, 7, 64));
        if (a) carved++;
      }
    }
    expect(carved, greaterThan(0));
    final low = CaveCarver(
      cave: simplexNoise(1, 0.05, 2),
      cavern: simplexNoise(2, 0.02, 2),
      seaLevel: 46,
      mouthThreshold: 2,
    );
    for (var x = 0; x < 64; x++) {
      expect(low.carved(x, 62, 7, 64), isFalse, reason: 'two below the surface is too shallow without a mouth');
    }
  });

  group('TreeCanvas', () {
    TreeCanvas canvas({int ground = 10}) => TreeCanvas(
      isSoft: (id) => id == _leaves,
      groundAt: (x, z) => ground,
      floorY: 5,
      hash: (x, y, z) => worldHash(3, x, y, z),
    );

    test('keeps what joins the stump by faces, drops what floats', () {
      final c = canvas();
      c.begin(8, 10, 8);
      for (var y = 10; y < 15; y++) {
        c.ink(8, y, 8, _log);
      }
      c.ink(8, 15, 8, _leaves); // on the trunk
      c.ink(9, 16, 9, _leaves); // an edge away: floating
      c.ink(3, 20, 3, _leaves); // nowhere near
      final w = ChunkWriter(_chunk(), 0, 0);
      c.print(w);
      expect(w.get(8, 15, 8), _leaves);
      expect(w.get(9, 16, 9), 0);
      expect(w.get(3, 20, 3), 0);
      expect(w.blocks.where((b) => b == _log), hasLength(5));
    });

    test('a tree across a border prints the same halves into both chunks', () {
      final c = canvas();
      void tree() {
        c.begin(15, 10, 8);
        Trees.oak(c, 15, 10, 8, 9, 12345, const TreeBlocks(log: _log, leaves: _leaves));
      }

      final left = ChunkWriter(_chunk(), 0, 0), right = ChunkWriter(_chunk(), 1, 0);
      tree();
      c.print(left);
      tree();
      c.print(right);
      final whole = <(int, int, int)>{};
      for (final w in [left, right]) {
        for (var x = w.ox; x < w.ox + 16; x++) {
          for (var y = 1; y < 40; y++) {
            for (var z = 0; z < 16; z++) {
              if (w.get(x, y, z) != 0) whole.add((x, y, z));
            }
          }
        }
      }
      expect(
        whole.where((p) => p.$1 == 15 && p.$3 == 8 && p.$2 >= 10 && p.$2 <= 19),
        hasLength(10),
        reason: 'the whole trunk',
      );
      expect(whole.where((p) => p.$1 >= 16), isNotEmpty, reason: 'the crown reaches the right chunk');
      expect(whole.every((p) => p.$2 >= 10), isTrue, reason: 'nothing in the ground');
    });

    test('nothing is printed into the ground or under the floor', () {
      final c = canvas(ground: 12);
      c.begin(8, 10, 8); // a stump sunk two blocks in the ground
      c.ink(8, 10, 8, _log);
      c.ink(8, 11, 8, _log);
      c.ink(8, 12, 8, _log);
      final w = ChunkWriter(_chunk(), 0, 0);
      c.print(w);
      expect(w.blocks.where((b) => b != 0), isEmpty, reason: 'its only grounded blocks are in the ground');
    });
  });
}
