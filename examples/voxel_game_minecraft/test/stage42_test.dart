import 'dart:math' as math;
import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/world/terrain_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage 42: nothing of a tree floats. Every block a tree writes touches the
/// next by a face, the walk back down those faces always ends on the ground,
/// and the ground is never water.
void main() {
  final gen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 1337);
  final water = Blocks.indexOf('water'), ice = Blocks.indexOf('ice'), sand = Blocks.indexOf('sand');
  final palm = Blocks.indexOf('jungle_log');
  final logs = {Blocks.indexOf('oak_log'), Blocks.indexOf('spruce_log'), palm};
  final soft = {Blocks.indexOf('oak_leaves'), Blocks.indexOf('spruce_leaves'), Blocks.indexOf('vines')};
  bool isTree(int id) => logs.contains(id) || soft.contains(id);

  ({int x, int z})? nearest(int biome) {
    for (var ring = 0; ring <= 120; ring++) {
      for (var dz = -ring; dz <= ring; dz++) {
        for (var dx = -ring; dx <= ring; dx++) {
          if (math.max(dx.abs(), dz.abs()) != ring) continue;
          if (gen.biomeAt(dx * 16 + 8, dz * 16 + 8) == biome) return (x: dx, z: dz);
        }
      }
    }
    return null;
  }

  /// A 5x5 of chunks read as one block of world, addressed from its middle
  /// chunk, so a tree that crosses a border is judged whole. The middle 3x3 is
  /// what a test judges; the ring around it is only there to hold up the trees
  /// that lean in.
  const pad = 2;
  ({int Function(int, int, int) at, int cx, int cz}) region(int cx, int cz) {
    const w = pad * 2 + 1;
    final grid = <int, Uint8List>{};
    for (var dz = -pad; dz <= pad; dz++) {
      for (var dx = -pad; dx <= pad; dx++) {
        grid[(dz + pad) * w + dx + pad] = gen.generate(cx + dx, cz + dz);
      }
    }
    int at(int x, int y, int z) {
      if (y < 0 || y >= 128) return -1;
      final gx = (x / 16).floor() + pad, gz = (z / 16).floor() + pad;
      if (gx < 0 || gx >= w || gz < 0 || gz >= w) return -1;
      return grid[gz * w + gx]![TerrainGenerator.index(x - (gx - pad) * 16, y, z - (gz - pad) * 16)];
    }

    return (at: at, cx: cx, cz: cz);
  }

  int key(int x, int y, int z) => ((x + 64) * 256 + y) * 256 + z + 64;

  /// Every tree block the six faces reach, starting from the blocks that stand
  /// on something that is neither tree nor water. [overLogs] walks trunks only.
  Set<int> standing(int Function(int, int, int) at, {required bool overLogs}) {
    bool part(int id) => overLogs ? logs.contains(id) : isTree(id);
    final seen = <int>{};
    final walk = <int>[];
    for (var z = -32; z < 48; z++) {
      for (var x = -32; x < 48; x++) {
        for (var y = 1; y < 128; y++) {
          if (!part(at(x, y, z))) continue;
          final below = at(x, y - 1, z);
          if (below <= 0 || below == water || below == ice || isTree(below)) continue;
          if (seen.add(key(x, y, z))) walk.add(key(x, y, z));
        }
      }
    }
    for (var q = 0; q < walk.length; q++) {
      final k = walk[q];
      final z = k % 256 - 64, y = (k ~/ 256) % 256, x = k ~/ 65536 - 64;
      for (final (dx, dy, dz) in const [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]) {
        if (!part(at(x + dx, y + dy, z + dz))) continue;
        if (seen.add(key(x + dx, y + dy, z + dz))) walk.add(key(x + dx, y + dy, z + dz));
      }
    }
    return seen;
  }

  test('a tree holds together: every block of it walks home by its faces', () {
    for (final biome in [
      TerrainGenerator.biomeForest,
      TerrainGenerator.biomeJungle,
      TerrainGenerator.biomeSnow,
      TerrainGenerator.biomeSwamp,
    ]) {
      final c = nearest(biome)!;
      final r = region(c.x, c.z);
      final held = standing(r.at, overLogs: false);
      final trunks = standing(r.at, overLogs: true);
      var blocks = 0, adrift = 0, cut = 0;
      for (var z = -16; z < 32; z++) {
        for (var x = -16; x < 32; x++) {
          for (var y = 1; y < 128; y++) {
            final id = r.at(x, y, z);
            if (!isTree(id)) continue;
            blocks++;
            if (!held.contains(key(x, y, z))) adrift++;
            // A trunk joined to the ground by a corner alone never gets walked.
            if (logs.contains(id) && !trunks.contains(key(x, y, z))) cut++;
          }
        }
      }
      expect(blocks, greaterThan(100), reason: 'biome $biome grew almost nothing');
      expect(adrift, 0, reason: 'biome $biome: $adrift leaves floating on their own');
      expect(cut, 0, reason: 'biome $biome: $cut logs joined to nothing by a face');
    }
  });

  test('no tree stands in the sea', () {
    final c = nearest(TerrainGenerator.biomeBeach)!;
    var trunks = 0, wet = 0, drowned = 0;
    for (var dz = -3; dz <= 3; dz++) {
      for (var dx = -3; dx <= 3; dx++) {
        final b = gen.generate(c.x + dx, c.z + dz);
        for (var z = 0; z < 16; z++) {
          for (var x = 0; x < 16; x++) {
            for (var y = 1; y < 128; y++) {
              final id = b[TerrainGenerator.index(x, y, z)];
              if (!isTree(id)) continue;
              if (y <= TerrainGenerator.seaLevel) drowned++;
              if (!logs.contains(id)) continue;
              trunks++;
              final below = b[TerrainGenerator.index(x, y - 1, z)];
              if (below == water || below == ice) wet++;
            }
          }
        }
      }
    }
    expect(trunks, greaterThan(0), reason: 'the shore grew no tree at all');
    expect(wet, 0, reason: '$wet logs resting on water');
    expect(drowned, 0, reason: '$drowned tree blocks under the sea');
  });

  test('the palm leans by faces, never off a corner', () {
    final c = nearest(TerrainGenerator.biomeDesert)!;
    var palms = 0, leaning = 0;
    for (var dz = -3; dz <= 3 && palms < 3; dz++) {
      for (var dx = -3; dx <= 3 && palms < 3; dx++) {
        final r = region(c.x + dx, c.z + dz);
        final trunks = standing(r.at, overLogs: true);
        for (var z = 0; z < 16; z++) {
          for (var x = 0; x < 16; x++) {
            final g = gen.surfaceHeight(r.cx * 16 + x, r.cz * 16 + z);
            if (g < 1 || r.at(x, g, z) != palm || r.at(x, g - 1, z) != sand) continue;
            palms++;
            // The whole trunk is reachable from its foot: eight blocks at least,
            // and the top of a leaning one no longer sits over its own foot.
            var top = g, lean = false;
            for (var y = g; y < g + 16; y++) {
              for (var ddz = -3; ddz <= 3; ddz++) {
                for (var ddx = -3; ddx <= 3; ddx++) {
                  if (r.at(x + ddx, y, z + ddz) != palm) continue;
                  if (!trunks.contains(key(x + ddx, y, z + ddz))) continue;
                  if (y > top) top = y;
                  if (ddx != 0 || ddz != 0) lean = true;
                }
              }
            }
            expect(top - g, greaterThanOrEqualTo(8), reason: 'a palm cut short at ${top - g} blocks');
            if (lean) leaning++;
          }
        }
      }
    }
    expect(palms, greaterThan(0), reason: 'the desert grew no palm');
    expect(leaning, greaterThan(0), reason: 'no palm leans any more');
  });

  test('a village is a clearing, not a wood cut off at the knees', () {
    ({int x, int z})? found;
    for (var cz = -40; cz <= 40 && found == null; cz += 6) {
      for (var cx = -40; cx <= 40 && found == null; cx += 6) {
        for (final s in gen.structuresNear(cx, cz)) {
          if (s.type != TerrainGenerator.structVillage) continue;
          found = (x: s.x, z: s.z);
          break;
        }
      }
    }
    expect(found, isNotNull, reason: 'no village within 40 chunks of the origin');
    final v = found!;
    var inside = 0;
    for (var cz = -2; cz <= 2; cz++) {
      for (var cx = -2; cx <= 2; cx++) {
        final ccx = (v.x / 16).floor() + cx, ccz = (v.z / 16).floor() + cz;
        final b = gen.generate(ccx, ccz);
        for (var z = 0; z < 16; z++) {
          for (var x = 0; x < 16; x++) {
            final wx = ccx * 16 + x, wz = ccz * 16 + z;
            final dx = wx - v.x, dz = wz - v.z;
            if (dx * dx + dz * dz > 24 * 24) continue;
            for (var y = 1; y < 128; y++) {
              // The well's corner posts are oak logs: they are the village's own.
              if (soft.contains(b[TerrainGenerator.index(x, y, z)]) && dx * dx + dz * dz > 9) inside++;
            }
          }
        }
      }
    }
    expect(inside, 0, reason: '$inside leaves left hanging over the village');
  });
}
