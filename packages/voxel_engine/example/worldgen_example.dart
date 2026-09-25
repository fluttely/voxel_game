// A world in one declaration: `dart run example/worldgen_example.dart`
// prints a map of it (one character per 24 x 24 blocks) and generates a few
// chunks on the core's worker isolates.
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/worldgen.dart';

const blocks = ['air', 'stone', 'dirt', 'grass', 'sand', 'water', 'log', 'leaves', 'coal_ore', 'snow', 'cobblestone'];
final Map<String, int> ids = {for (var i = 0; i < blocks.length; i++) blocks[i]: i};

const WorldGenSpec world = WorldGenSpec(
  biomes: [
    Biome(
      'tundra',
      top: 'snow',
      under: 'dirt',
      climate: Climate.cold,
      trees: [TreeSpec.spruce(log: 'log', leaves: 'leaves')],
      treeChance: 30,
    ),
    Biome('desert', top: 'sand', climate: Climate.hotDry),
    Biome(
      'forest',
      top: 'grass',
      under: 'dirt',
      climate: Climate.wet,
      trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')],
      treeChance: 90,
    ),
    Biome(
      'plains',
      top: 'grass',
      under: 'dirt',
      trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')],
      treeChance: 15,
    ),
  ],
  beach: Biome('beach', top: 'sand'),
  ores: [Ore('coal_ore', share: 0.11)],
  structures: [
    StructureSpec('tower', build: tower, biomes: ['plains', 'forest'], radius: 3),
  ],
);

/// A cobblestone tower with a door, drawn around its site on the surface.
void tower(StructureSite s) {
  s.level(-2, -2, 2, 2, 'cobblestone', clearTo: 10);
  s.fill(-2, 0, -2, 2, 7 + s.roll(1) % 4, 2, 'cobblestone', hollow: true);
  s.fill(0, 1, 2, 0, 2, 2, 'air');
}

/// The worker isolates build their generator with this: top-level, so it is
/// sendable.
ChunkGenerator makeGenerator() => world.compile(ids, 2024);

Future<void> main() async {
  final g = world.compile(ids, 2024);
  const glyph = {'tundra': '*', 'desert': ':', 'forest': 'T', 'plains': '"', 'beach': '.'};
  final towers = <(int, int)>{
    for (var cx = -40; cx <= 40; cx += 6)
      for (var cz = -20; cz <= 20; cz += 6)
        for (final s in g.structuresNear(cx, cz)) (s.x ~/ 24, s.z ~/ 24),
  };
  for (var z = -12; z <= 12; z++) {
    final row = StringBuffer();
    for (var x = -30; x <= 30; x++) {
      final h = g.surfaceHeight(x * 24, z * 24);
      row.write(towers.contains((x, z)) ? '#' : (h <= world.seaLevel ? '~' : glyph[g.biomeAt(x * 24, z * 24).name]));
    }
    print(row);
  }
  print('~ sea  . beach  " plains  T forest  : desert  * tundra  # tower');

  final table = VoxelBlockTable([
    const VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
    for (var i = 1; i < blocks.length; i++)
      const VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.5),
  ]);
  final pool = ChunkWorkerPool(ChunkWorkerConfig(generator: makeGenerator, table: table));
  await pool.start();
  final watch = Stopwatch()..start();
  final chunks = await Future.wait([for (var i = 0; i < 25; i++) pool.generate(i % 5, i ~/ 5)]);
  final solid = chunks.fold<int>(0, (n, c) => n + c.where((b) => b != 0).length);
  print('25 chunks on ${pool.workers} isolates in ${watch.elapsedMilliseconds} ms, $solid blocks');
  pool.dispose();
}
