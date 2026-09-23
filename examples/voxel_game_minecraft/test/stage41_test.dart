import 'dart:math' as math;

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/world/terrain_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage 41's trees: the patch grid that spaces them, the clearance under the
/// crowns, the height of the trunks and the palm of the sand.
void main() {
  final gen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 1337);
  final logs = {
    Blocks.indexOf('oak_log'),
    Blocks.indexOf('spruce_log'),
    Blocks.indexOf('jungle_log'),
  };
  final leaves = {Blocks.indexOf('oak_leaves'), Blocks.indexOf('spruce_leaves')};

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

  test('one tree to a patch: no two spots closer than five blocks', () {
    final spots = <({int x, int z})>{};
    for (var z = -200; z < 200; z++) {
      for (var x = -200; x < 200; x++) {
        final p = gen.treePatchOf(x, z);
        spots.add((x: p.x, z: p.z));
      }
    }
    // Every column of a patch names the same spot, and the spot is inside it.
    expect(spots.length, greaterThan(2000));
    var min = 1e9;
    for (final a in spots) {
      for (final b in spots) {
        if (a.x == b.x && a.z == b.z) continue;
        if ((a.x - b.x).abs() > 8 || (a.z - b.z).abs() > 8) continue;
        final d = math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.z - b.z, 2));
        if (d < min) min = d;
      }
    }
    expect(min, greaterThanOrEqualTo(5.0));
  });

  /// Everything a body meets in a 5x5-chunk square: the columns it cannot stand
  /// in, the lowest leaf over the ground and the tallest trunk.
  ({double blocked, int lowestLeaf, int tallest, int trees}) survey(({int x, int z}) c) {
    var blocked = 0, columns = 0, lowestLeaf = 99, tallest = 0, trees = 0;
    for (var dz = -2; dz <= 2; dz++) {
      for (var dx = -2; dx <= 2; dx++) {
        final b = gen.generate(c.x + dx, c.z + dz);
        final ox = (c.x + dx) * 16, oz = (c.z + dz) * 16;
        for (var z = 0; z < 16; z++) {
          for (var x = 0; x < 16; x++) {
            final g = gen.surfaceHeight(ox + x, oz + z);
            columns++;
            var trunk = 0;
            var standing = true;
            for (var y = g; y < math.min(g + 40, 128); y++) {
              final id = b[TerrainGenerator.index(x, y, z)];
              if (logs.contains(id)) {
                if (y == g) trunk = 1;
                if (trunk == y - g) trunk = y - g + 1;
              } else if (leaves.contains(id) && y - g < lowestLeaf) {
                lowestLeaf = y - g;
              }
              if (y <= g + 1 && (logs.contains(id) || leaves.contains(id))) standing = false;
            }
            if (!standing) blocked++;
            if (trunk > 0) trees++;
            if (trunk > tallest) tallest = trunk;
          }
        }
      }
    }
    return (blocked: blocked / columns, lowestLeaf: lowestLeaf, tallest: tallest, trees: trees);
  }

  test('a wood is walked through: knees and head clear, crowns overhead', () {
    for (final biome in [
      TerrainGenerator.biomeForest,
      TerrainGenerator.biomeJungle,
      TerrainGenerator.biomeSnow,
      TerrainGenerator.biomeSwamp,
    ]) {
      final c = nearest(biome)!;
      final s = survey(c);
      expect(s.trees, greaterThan(20), reason: 'biome $biome');
      // Under three per cent of the ground is trunk; it was over four (a snow
      // forest was thirty), because a crown used to start at the knee.
      expect(s.blocked, lessThan(0.03), reason: 'biome $biome blocked ${s.blocked}');
      expect(s.lowestLeaf, greaterThanOrEqualTo(4), reason: 'biome $biome leaf +${s.lowestLeaf}');
      // The trunks are the tall ones now: the old oak was four to six blocks.
      expect(s.tallest, greaterThanOrEqualTo(13), reason: 'biome $biome trunk ${s.tallest}');
    }
  });

  test('the sand grows palms: a jungle-log trunk over sand, fronds on top', () {
    final c = nearest(TerrainGenerator.biomeDesert)!;
    final sand = Blocks.indexOf('sand'), palm = Blocks.indexOf('jungle_log');
    var palms = 0;
    for (var dz = -3; dz <= 3; dz++) {
      for (var dx = -3; dx <= 3; dx++) {
        final b = gen.generate(c.x + dx, c.z + dz);
        final ox = (c.x + dx) * 16, oz = (c.z + dz) * 16;
        for (var z = 0; z < 16; z++) {
          for (var x = 0; x < 16; x++) {
            final g = gen.surfaceHeight(ox + x, oz + z);
            if (g < 1 || b[TerrainGenerator.index(x, g, z)] != palm) continue;
            if (b[TerrainGenerator.index(x, g - 1, z)] != sand) continue;
            palms++;
          }
        }
      }
    }
    expect(palms, greaterThan(0));
    expect(TerrainGenerator.treeChance(TerrainGenerator.biomeDesert), greaterThan(0));
    expect(TerrainGenerator.treeChance(TerrainGenerator.biomeBeach), greaterThan(0));
    // The ocean has none; the forest has the most.
    expect(TerrainGenerator.treeChance(TerrainGenerator.biomeOcean), 0);
    expect(TerrainGenerator.treeChance(TerrainGenerator.biomeForest), greaterThan(80));
  });
}
