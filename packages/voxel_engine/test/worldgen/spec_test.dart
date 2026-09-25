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
    Biome('tundra', top: 'snow', climate: Climate.cold, ice: 'ice'),
    Biome('desert', top: 'sand', climate: Climate.hotDry),
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
    StructureSpec('hut', build: _hut, chance: 1.0, biomes: ['plains'], radius: 4, regionChunks: 3),
  ],
);

/// Top-level, as a worker isolate's generator factory must be.
ChunkGenerator _worldFactory() => _world.compile(_ids, 7);

int _count(Uint8List b, int id) => b.where((v) => v == id).length;

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

  test('the spec crosses to the worker isolates', () async {
    final pool = ChunkWorkerPool(ChunkWorkerConfig(generator: _worldFactory, table: _table), workers: 2);
    await pool.start();
    try {
      final remote = await pool.generate(2, 3);
      expect(remote, _world.compile(_ids, 7).generateIn(2, 3, 0));
    } finally {
      pool.dispose();
    }
  });
}
