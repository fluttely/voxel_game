import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/worldgen.dart';

const List<String> _names = [
  'stone', 'deep', 'dirt', 'grass', 'snow', 'sand', 'water', 'mud', 'log', 'leaves', //
  'spruce', 'needles', 'cactus', 'melon', 'reeds', 'flower', 'bedrock', 'coal_ore',
];
final Map<String, int> _ids = {for (var i = 0; i < _names.length; i++) _names[i]: i + 1};
int _id(String name) => _ids[name]!;

/// A flat world at height [height] over a sea at 10, no caves.
WorldGenSpec _flat(Biome biome, {int height = 20, List<Stratum> strata = const []}) => WorldGenSpec(
  terrain: TerrainRecipe.flat(height),
  seaLevel: 10,
  bedrock: 'bedrock',
  caves: CaveSpec.none,
  strata: strata,
  biomes: [biome],
);

int _at(Uint8List c, int x, int y, int z) => c[ChunkSize.index(x, y, z)];

/// The block at world ([x], [y], [z]) of [g], generating its chunk.
int _world(SpecGenerator g, int x, int y, int z) =>
    _at(g.generateIn(floorDiv(x, 16), floorDiv(z, 16), 0), x & 15, y, z & 15);

void main() {
  test('strata take the rock below their heights, the first that holds winning', () {
    final g = _flat(
      const Biome('plains', top: 'grass', under: 'dirt'),
      strata: const [Stratum('bedrock', belowY: 3), Stratum('deep', belowY: 10)],
    ).compile(_ids, 1);
    final c = g.generateIn(0, 0, 0);
    expect(_at(c, 4, 2, 4), _id('bedrock'));
    expect(_at(c, 4, 9, 4), _id('deep'));
    expect(_at(c, 4, 10, 4), _id('stone'));
  });

  test('ores vein a stratum as they vein stone', () {
    final g = WorldGenSpec(
      terrain: const TerrainRecipe.flat(60),
      caves: CaveSpec.none,
      strata: const [Stratum('deep', belowY: 30)],
      ores: const [Ore('coal_ore', share: 0.3)],
      biomes: const [Biome('plains', top: 'grass')],
    ).compile(_ids, 1);
    final c = g.generateIn(0, 0, 0);
    var deep = 0, coalDeep = 0;
    for (var i = 0; i < 256; i++) {
      for (var y = 1; y < 30; y++) {
        final id = _at(c, i % 16, y, i ~/ 16);
        if (id == _id('deep')) deep++;
        if (id == _id('coal_ore')) coalDeep++;
      }
    }
    expect(deep, greaterThan(0));
    expect(coalDeep, greaterThan(0));
  });

  test('a cover takes the top in its window of height', () {
    const snowy = Biome('peaks', top: 'grass', covers: [Cover('snow', minHeight: 20)]);
    const low = Biome('peaks', top: 'grass', covers: [Cover('snow', maxHeight: 19)]);
    expect(_at(_flat(snowy).compile(_ids, 1).generateIn(0, 0, 0), 3, 19, 3), _id('snow'));
    expect(_at(_flat(low).compile(_ids, 1).generateIn(0, 0, 0), 3, 19, 3), _id('grass'));
  });

  test('a cover rolls by patch: its share of the patches, each patch whole', () {
    const mud = Biome('swamp', top: 'grass', covers: [Cover('mud', perMille: 400, patch: 4)]);
    final g = _flat(mud).compile(_ids, 3);
    var covered = 0, patches = 0;
    for (var cz = 0; cz < 4; cz++) {
      for (var cx = 0; cx < 4; cx++) {
        final c = g.generateIn(cx, cz, 0);
        for (var pz = 0; pz < 16; pz += 4) {
          for (var px = 0; px < 16; px += 4) {
            final first = _at(c, px, 19, pz);
            for (var i = 0; i < 16; i++) {
              expect(_at(c, px + i % 4, 19, pz + i ~/ 4), first, reason: 'a patch is one roll');
            }
            patches++;
            if (first == _id('mud')) covered++;
          }
        }
      }
    }
    expect(covered / patches, inInclusiveRange(0.25, 0.55));
  });

  group('pools', () {
    const swamp = Biome(
      'swamp',
      top: 'grass',
      under: 'dirt',
      pools: Pools(bed: 'mud', threshold: 0.1),
    );

    test('lie one deep, water over the bed, wherever the noise runs high on level ground', () {
      final g = _flat(swamp).compile(_ids, 5);
      var pools = 0;
      for (var cx = 0; cx < 3; cx++) {
        final c = g.generateIn(cx, 0, 0);
        for (var i = 0; i < 256; i++) {
          final x = i % 16, z = i ~/ 16;
          if (_at(c, x, 19, z) != _id('water')) continue;
          pools++;
          expect(_at(c, x, 18, z), _id('mud'));
          expect(_at(c, x, 20, z), 0);
        }
      }
      expect(pools, greaterThan(20));
    });

    test('never stand beside lower ground or over a cave, so the water stays put', () {
      const spec = WorldGenSpec(
        biomes: [
          Biome(
            'swamp',
            top: 'grass',
            under: 'dirt',
            pools: Pools(bed: 'mud', threshold: 0.1),
          ),
        ],
        ores: [Ore('coal_ore', share: 0.1)],
      );
      final g = spec.compile(_ids, 11);
      var pools = 0;
      for (var cx = -3; cx <= 3; cx++) {
        for (var cz = -3; cz <= 3; cz++) {
          final c = g.generateIn(cx, cz, 0);
          for (var i = 0; i < 256; i++) {
            final x = i % 16, z = i ~/ 16, wx = cx * 16 + x, wz = cz * 16 + z;
            final h = g.surfaceHeight(wx, wz);
            if (h <= spec.seaLevel || _at(c, x, h - 1, z) != _id('water')) continue;
            pools++;
            expect(_at(c, x, h - 2, z), _id('mud'));
            for (final (dx, dz) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
              expect(g.surfaceHeight(wx + dx, wz + dz), greaterThanOrEqualTo(h));
              final nx = x + dx, nz = z + dz;
              if (nx < 0 || nx > 15 || nz < 0 || nz > 15) continue;
              expect(_at(c, nx, h - 1, nz), isNot(0), reason: 'a wall of ground or water beside a pool');
            }
          }
        }
      }
      expect(pools, greaterThan(0));
    });
  });

  test('trees are picked by weight', () {
    const wood = Biome(
      'wood',
      top: 'grass',
      treeChance: 100,
      trees: [
        TreeSpec.oak(log: 'log', leaves: 'leaves', weight: 3),
        TreeSpec.spruce(log: 'spruce', leaves: 'needles'),
      ],
    );
    final g = _flat(wood).compile(_ids, 9);
    var oaks = 0, spruces = 0;
    for (var cx = 0; cx < 6; cx++) {
      for (var cz = 0; cz < 6; cz++) {
        final c = g.generateIn(cx, cz, 0);
        for (var i = 0; i < 256; i++) {
          final foot = _at(c, i % 16, 20, i ~/ 16);
          if (foot == _id('log')) oaks++;
          if (foot == _id('spruce')) spruces++;
        }
      }
    }
    expect(oaks + spruces, greaterThan(60));
    expect(oaks / (oaks + spruces), inInclusiveRange(0.62, 0.88));
  });

  test('a tree grows only on ground below its height', () {
    const high = Biome(
      'wood',
      top: 'grass',
      treeChance: 100,
      trees: [TreeSpec.oak(log: 'log', leaves: 'leaves', belowY: 20)],
    );
    final c = _flat(high).compile(_ids, 9).generateIn(0, 0, 0);
    expect(c.where((b) => b == _id('log')), isEmpty);
  });

  test('a plant stands its height to its most', () {
    const desert = Biome('desert', top: 'sand', plants: [Plant('cactus', perMille: 1000, height: 2, maxHeight: 3)]);
    final c = _flat(desert).compile(_ids, 4).generateIn(0, 0, 0);
    final heights = <int>{};
    for (var i = 0; i < 256; i++) {
      var tall = 0;
      while (_at(c, i % 16, 20 + tall, i ~/ 16) == _id('cactus')) {
        tall++;
      }
      heights.add(tall);
    }
    expect(heights, {2, 3});
  });

  test('a spreading plant grows on its neighbours too, across chunk borders', () {
    const jungle = Biome('jungle', top: 'grass', plants: [Plant('melon', perMille: 40, spread: 2)]);
    final g = _flat(jungle).compile(_ids, 6);
    final chunks = [for (var cx = 0; cx < 8; cx++) g.generateIn(cx, 0, 0)];
    var paired = 0, acrossBorder = 0;
    for (var cx = 0; cx < chunks.length; cx++) {
      final c = chunks[cx];
      for (var i = 0; i < 256; i++) {
        final x = i % 16, z = i ~/ 16;
        if (_at(c, x, 20, z) != _id('melon')) continue;
        if (x < 15 && _at(c, x + 1, 20, z) == _id('melon')) paired++;
        if (z < 15 && _at(c, x, 20, z + 1) == _id('melon')) paired++;
        if (x == 15 && cx + 1 < chunks.length && _at(chunks[cx + 1], 0, 20, z) == _id('melon')) acrossBorder++;
      }
    }
    expect(paired, greaterThan(10));
    expect(acrossBorder, greaterThan(0), reason: 'a patch at a border is drawn by both chunks');
    // A melon on its own column's roll or a neighbour's, the same either side of a border.
    final g2 = _flat(jungle).compile(_ids, 6);
    expect(g2.generateIn(3, 0, 0), chunks[3]);
  });

  test('a plant that seeks water grows beside it, and away from it the next plant takes the roll', () {
    const marsh = Biome(
      'marsh',
      top: 'grass',
      under: 'dirt',
      pools: Pools(bed: 'mud', threshold: 0.1),
      plants: [Plant('reeds', perMille: 1000, byWater: true), Plant('flower', perMille: 1000)],
    );
    final g = _flat(marsh).compile(_ids, 5);
    bool water(int x, int z) => _world(g, x, 19, z) == _id('water');
    var reeds = 0, flowers = 0;
    for (var x = 1; x < 47; x++) {
      for (var z = 1; z < 15; z++) {
        final plant = _world(g, x, 20, z);
        if (water(x, z)) {
          expect(plant, 0, reason: 'nothing grows in a pool');
          continue;
        }
        final beside = water(x + 1, z) || water(x - 1, z) || water(x, z + 1) || water(x, z - 1);
        expect(plant, beside ? _id('reeds') : _id('flower'));
        beside ? reeds++ : flowers++;
      }
    }
    expect(reeds, greaterThan(0));
    expect(flowers, greaterThan(0));
  });

  test('a cavern refuses pools and plants that spread or seek water', () {
    WorldGenSpec cavern(Biome b) =>
        WorldGenSpec(cavern: const CavernSpec(), caves: CaveSpec.none, bedrock: 'bedrock', biomes: [b]);
    expect(
      () => cavern(
        const Biome(
          'b',
          top: 'sand',
          pools: Pools(bed: 'mud'),
        ),
      ).compile(_ids, 1),
      throwsArgumentError,
    );
    expect(
      () => cavern(const Biome('b', top: 'sand', plants: [Plant('melon', perMille: 1, spread: 1)])).compile(_ids, 1),
      throwsArgumentError,
    );
    expect(
      () =>
          cavern(const Biome('b', top: 'sand', plants: [Plant('reeds', perMille: 1, byWater: true)])).compile(_ids, 1),
      throwsArgumentError,
    );
  });

  test('a cavern\'s floors take their covers and its rock its strata', () {
    final g = const WorldGenSpec(
      cavern: CavernSpec(),
      caves: CaveSpec.none,
      seaLevel: 28,
      bedrock: 'bedrock',
      strata: [Stratum('deep', belowY: 40)],
      biomes: [
        Biome('b', top: 'sand', under: 'dirt', covers: [Cover('snow', minHeight: 60)]),
      ],
    ).compile(_ids, 3);
    final c = g.generateIn(0, 0, 0);
    var snowHigh = 0, sandHigh = 0, deep = 0, stoneDeep = 0;
    for (var i = 0; i < 256; i++) {
      for (var y = 8; y < 100; y++) {
        final id = _at(c, i % 16, y, i ~/ 16);
        if (id == _id('snow')) {
          expect(y, greaterThanOrEqualTo(59));
          snowHigh++;
        }
        if (id == _id('sand') && y >= 59) sandHigh++;
        if (y < 40 && id == _id('deep')) deep++;
        if (y < 40 && id == _id('stone')) stoneDeep++;
      }
    }
    expect(snowHigh, greaterThan(0));
    expect(sandHigh, 0);
    expect(deep, greaterThan(0));
    expect(stoneDeep, 0);
  });
}
