import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/worldgen.dart';

const Map<String, int> _ids = {
  'stone': 1, 'dirt': 2, 'grass': 3, 'sand': 4, 'water': 5, 'log': 6, 'leaves': 7, //
  'coal_ore': 8, 'bedrock': 9, 'flower': 10, 'cobblestone': 11, 'lava': 12, 'ice': 13, 'snow': 14,
};

final VoxelBlockTable _table = VoxelBlockTable([
  const VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  for (var i = 1; i < 15; i++)
    const VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.5),
]);

void _hut(StructureSite s) {
  s.level(-2, -2, 2, 2, 'cobblestone');
  s.fill(-2, 0, -2, 2, 3, 2, 'cobblestone', hollow: true);
  s.put(0, 1, 2, 'air'); // the door
}

const WorldGenSpec _world = WorldGenSpec(
  bedrock: 'bedrock',
  biomes: [
    Biome('tundra', top: 'snow', climate: Climate.cold, ice: 'ice', precipitation: Precipitation.snow),
    Biome('desert', top: 'sand', climate: Climate.hotDry, precipitation: Precipitation.none),
    Biome(
      'plains',
      top: 'grass',
      under: 'dirt',
      trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')],
      treeChance: 60,
      plants: [Plant('flower', perMille: 100)],
    ),
  ],
  beach: Biome('beach', top: 'sand'),
  ores: [Ore('coal_ore', share: 0.2)],
  caves: CaveSpec(lava: 'lava'),
  structures: [
    StructureSpec('hut', CustomStructure(_hut, radius: 4), chance: 1.0, biomes: ['plains'], regionChunks: 3),
  ],
);

/// An underworld: lava up to 28, sand floors where it is wet, flowers hanging.
const WorldGenSpec _cavern = WorldGenSpec(
  cavern: CavernSpec(hangs: [Plant('flower', perMille: 200, height: 2)]),
  stone: 'cobblestone',
  water: 'lava',
  seaLevel: 28,
  bedrock: 'bedrock',
  caves: CaveSpec.none,
  biomes: [
    Biome('valley', top: 'sand', climate: Climate.wet, precipitation: Precipitation.none),
    Biome('wastes', top: 'cobblestone', precipitation: Precipitation.none),
  ],
  ores: [Ore('coal_ore', share: 0.1)],
);

/// Top-level, as a worker isolate's generator factory must be.
ChunkGenerator _worldFactory() => _world.compile(_ids, 7);

ChunkGenerator _dimensionsFactory() => DimensionGenerator(const [_world, _cavern], _ids, 7);

int _count(Uint8List b, int id) => b.where((v) => v == id).length;

/// An FNV-1a hash of [bytes], to pin a world.
int _fingerprint(Iterable<int> bytes) {
  var h = 0x811c9dc5;
  for (final v in bytes) {
    h = ((h ^ v) * 0x01000193) & 0xffffffff;
  }
  return h;
}

void main() {
  test('a flat world is stone under soil under grass, bedrock at the bottom', () {
    const flat = WorldGenSpec(
      terrain: TerrainRecipe.flat(20),
      seaLevel: 10,
      bedrock: 'bedrock',
      caves: CaveSpec.none,
      biomes: [Biome('plains', top: 'grass', under: 'dirt')],
    );
    final g = flat.compile(_ids, 1);
    final c = g.generateIn(0, 0, 0);
    expect(g.surfaceHeight(123, -45), 20);
    expect(c[ChunkSize.index(3, 0, 3)], _ids['bedrock']);
    expect(c[ChunkSize.index(3, 15, 3)], _ids['stone']);
    expect(c[ChunkSize.index(3, 16, 3)], _ids['dirt']);
    expect(c[ChunkSize.index(3, 18, 3)], _ids['dirt']);
    expect(c[ChunkSize.index(3, 19, 3)], _ids['grass']);
    expect(c[ChunkSize.index(3, 20, 3)], 0);
    expect(g.biomeAt(0, 0).name, 'plains');
  });

  test('a biome says what falls on it, rain unless it says otherwise', () {
    final g = _world.compile(_ids, 7);
    final seen = <String, Precipitation>{};
    for (var x = -4000; x <= 4000 && seen.length < 4; x += 37) {
      for (var z = -4000; z <= 4000 && seen.length < 4; z += 173) {
        final b = g.biomeAt(x, z);
        seen[b.name] = b.precipitation;
      }
    }
    expect(seen, {
      'tundra': Precipitation.snow,
      'desert': Precipitation.none,
      'plains': Precipitation.rain,
      'beach': Precipitation.rain,
    });
  });

  test('a missing block fails at compile time, naming it', () {
    const bad = WorldGenSpec(biomes: [Biome('moon', top: 'cheese')]);
    expect(() => bad.compile(_ids, 1), throwsA(isA<ArgumentError>().having((e) => e.invalidValue, 'block', 'cheese')));
  });

  test('the continental world: every biome, ores, caves, trees and plants appear', () {
    final g = _world.compile(_ids, 7);
    final biomes = <String>{};
    for (var x = -3000; x <= 3000; x += 97) {
      for (var z = -3000; z <= 3000; z += 89) {
        biomes.add(g.biomeAt(x, z).name);
      }
    }
    expect(biomes, containsAll(['tundra', 'desert', 'plains', 'beach']));
    var coal = 0, logs = 0, flowers = 0, water = 0;
    for (var cx = -3; cx <= 3; cx++) {
      for (var cz = -3; cz <= 3; cz++) {
        final c = g.generateIn(cx, cz, 0);
        coal += _count(c, _ids['coal_ore']!);
        logs += _count(c, _ids['log']!);
        flowers += _count(c, _ids['flower']!);
        water += _count(c, _ids['water']!);
      }
    }
    expect(coal, greaterThan(0));
    expect(logs + flowers + water, greaterThan(0));
  });

  test('a world that uses none of the rows added since generates what it did before them', () {
    // Pinned on 2026-10-02, before strata, covers, pools, tree weights, plant
    // spreads and structures kept apart: a spec without them must not move.
    final g = _world.compile(_ids, 7), c = _cavern.compile(_ids, 3);
    expect(
      _fingerprint([
        for (var cx = -3; cx <= 3; cx++)
          for (var cz = -3; cz <= 3; cz++) _fingerprint(g.generateIn(cx, cz, 0)),
      ]),
      3858467787,
    );
    expect(
      _fingerprint([
        for (var cx = -2; cx <= 2; cx++)
          for (var cz = -2; cz <= 2; cz++) _fingerprint(c.generateIn(cx, cz, 0)),
      ]),
      2821150095,
    );
  });

  test('generation is pure: the same chunk twice, and another seed differs', () {
    final a = _world.compile(_ids, 7), b = _world.compile(_ids, 7), other = _world.compile(_ids, 8);
    expect(a.generateIn(4, -2, 0), b.generateIn(4, -2, 0));
    expect(a.generateIn(4, -2, 0), isNot(other.generateIn(4, -2, 0)));
  });

  test('a structure is found by every chunk around it and drawn across borders', () {
    final g = _world.compile(_ids, 7);
    PlacedStructure? hut;
    for (var cx = -20; cx <= 20 && hut == null; cx += 3) {
      for (var cz = -20; cz <= 20 && hut == null; cz += 3) {
        final near = g.structuresNear(cx, cz);
        if (near.isNotEmpty) hut = near.first;
      }
    }
    expect(hut, isNotNull, reason: 'chance 1.0 on plains finds one');
    final h = hut!;
    expect(g.biomeAt(h.x, h.z).name, 'plains');
    // The wall ring at y+1, every cell read from whichever chunk holds it.
    var wall = 0;
    for (var dx = -2; dx <= 2; dx++) {
      for (var dz = -2; dz <= 2; dz++) {
        if (dx.abs() != 2 && dz.abs() != 2) continue;
        final wx = h.x + dx, wz = h.z + dz;
        final c = g.generateIn(floorDiv(wx, 16), floorDiv(wz, 16), 0);
        final id = c[ChunkSize.index(wx - floorDiv(wx, 16) * 16, h.y + 1, wz - floorDiv(wz, 16) * 16)];
        if (id == _ids['cobblestone']) wall++;
      }
    }
    expect(wall, 15, reason: 'sixteen wall cells less the door');
  });

  test('a blueprint draws its layers with the legend, "." clearing', () {
    final w = ChunkWriter(Uint8List(ChunkSize.volume), 0, 0);
    w.put(5, 11, 5, 3);
    final site = StructureSite(
      name: 'x',
      x: 4,
      y: 10,
      z: 4,
      seed: 1,
      writer: w,
      block: (n) => _ids[n]!,
      surfaceAt: (x, z) => 10,
    );
    site.blueprint(
      [
        ['##', '#.'],
        ['.#'],
      ],
      {'#': 'cobblestone'},
    );
    expect(w.get(4, 10, 4), _ids['cobblestone']);
    expect(w.get(5, 10, 5), 0);
    expect(w.get(4, 11, 4), 0);
    expect(w.get(5, 11, 4), _ids['cobblestone']);
    expect(site.roll(1), site.roll(1));
  });

  group('a cavern', () {
    final g = _cavern.compile(_ids, 3);
    final chunks = [for (var cx = -2; cx < 2; cx++) g.generateIn(cx, 1, 0)];
    int at(Uint8List c, int x, int y, int z) => c[ChunkSize.index(x, y, z)];

    test('is a slab of rock between a bedrock floor and roof, open sky over it', () {
      for (final c in chunks) {
        for (var i = 0; i < 16 * 16; i++) {
          final x = i % 16, z = i ~/ 16;
          expect([at(c, x, 0, z), at(c, x, 7, z), at(c, x, 100, z)], everyElement(_ids['bedrock']));
          expect(at(c, x, 4, z), isIn([_ids['cobblestone'], _ids['coal_ore']]));
          expect(at(c, x, 101, z), 0);
        }
      }
    });

    test('opens into caverns, the sea filling them below its level', () {
      var open = 0, slab = 0, lavaAbove = 0, airBelow = 0;
      for (final c in chunks) {
        for (var y = 8; y < 100; y++) {
          for (var i = 0; i < 16 * 16; i++) {
            final id = at(c, i % 16, y, i ~/ 16);
            slab++;
            if (id == 0 || id == _ids['lava'] || id == _ids['flower']) open++;
            if (id == _ids['lava'] && y > 28) lavaAbove++;
            if (id == 0 && y <= 28) airBelow++;
          }
        }
      }
      expect(open / slab, inInclusiveRange(0.2, 0.6));
      expect(lavaAbove, 0);
      expect(airBelow, 0);
    });

    test('covers its floors with their biome, veins its rock and hangs things from its ceilings', () {
      final all = [for (final c in chunks) ...c];
      final ids = Uint8List.fromList(all);
      expect(_count(ids, _ids['sand']!) + _count(ids, _ids['cobblestone']!), greaterThan(0));
      expect(_count(ids, _ids['coal_ore']!), greaterThan(0));
      expect(_count(ids, _ids['flower']!), greaterThan(0));
      // Every hanging flower hangs: rock or another flower above it, never under the sea.
      for (final c in chunks) {
        for (var y = 8; y < 100; y++) {
          for (var i = 0; i < 16 * 16; i++) {
            final x = i % 16, z = i ~/ 16;
            if (at(c, x, y, z) != _ids['flower']) continue;
            expect(y, greaterThan(28));
            expect(at(c, x, y + 1, z), isNot(0));
          }
        }
      }
    });

    test('its surface is the lowest floor above the sea', () {
      var floors = 0;
      for (var x = -32; x < 32; x += 3) {
        final h = g.surfaceHeight(x, 20);
        expect(h, greaterThan(28));
        final c = g.generateIn(x >> 4, 20 >> 4, 0);
        final lx = x & 15, lz = 20 & 15;
        if (at(c, lx, h, lz) == 0 && at(c, lx, h - 1, lz) != 0 && at(c, lx, h - 1, lz) != _ids['lava']) floors++;
      }
      expect(floors, greaterThan(10), reason: 'most columns have a floor above the lava');
    });

    test('grows no trees and carves no caves', () {
      expect(
        () => WorldGenSpec(
          cavern: const CavernSpec(),
          caves: CaveSpec.none,
          biomes: [
            Biome(
              'wood',
              top: 'grass',
              trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')],
            ),
          ],
        ).compile(_ids, 1),
        throwsArgumentError,
      );
      expect(
        () => const WorldGenSpec(
          cavern: CavernSpec(),
          biomes: [Biome('rock', top: 'stone')],
        ).compile(_ids, 1),
        throwsArgumentError,
      );
    });
  });

  test('a world of dimensions hands each chunk to its dimension\'s generator', () {
    final g = DimensionGenerator(const [_world, _cavern], _ids, 7);
    expect(g.seed, 7);
    expect(g.generateIn(2, 3, 0), _world.compile(_ids, 7).generateIn(2, 3, 0));
    expect(g.generateIn(2, 3, 1), _cavern.compile(_ids, 7).generateIn(2, 3, 0));
    expect(g[1].spec, same(_cavern));
    expect(() => g.generateIn(0, 0, 2), throwsArgumentError);
    expect(() => DimensionGenerator(const [], _ids, 7), throwsArgumentError);
  });

  test('the spec crosses to the worker isolates', () async {
    final pool = ChunkWorkerPool(ChunkWorkerConfig(generator: _worldFactory, table: _table), workers: 2);
    await pool.start();
    try {
      final remote = await pool.generate(2, 3);
      expect(remote, _world.compile(_ids, 7).generateIn(2, 3, 0));
    } finally {
      pool.dispose();
    }
    final dims = ChunkWorkerPool(ChunkWorkerConfig(generator: _dimensionsFactory, table: _table), workers: 1);
    await dims.start();
    try {
      expect(await dims.generate(2, 3, 1), _cavern.compile(_ids, 7).generateIn(2, 3, 0));
    } finally {
      dims.dispose();
    }
  });
}
