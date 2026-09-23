import 'dart:math' as math;
import 'dart:typed_data';

import 'package:voxel_engine/core.dart';

import '../core/chunk_writer.dart';
import '../core/world_math.dart';
import '../features/cave_carver.dart';
import '../features/ore_table.dart';
import '../features/scatter_grid.dart';
import '../features/structure_grid.dart';
import '../features/tree_canvas.dart';
import '../features/trees.dart';
import '../noise/fast_noise_lite.dart';
import 'structure_site.dart';
import 'world_gen_spec.dart';

/// A structure placed in the world: what [SpecGenerator.structuresNear]
/// answers.
typedef PlacedStructure = ({String name, int x, int y, int z});

/// A [WorldGenSpec] compiled for one seed against one game's block ids: the
/// [ChunkGenerator] the worker isolates run, and the queries a game asks of
/// its terrain (a spawn point, the biome under the player, the structures on
/// the map). Pure in (seed, position), so every isolate agrees.
class SpecGenerator implements ChunkGenerator {
  /// The generator of [spec] for [seed]; throws [ArgumentError] when [ids]
  /// lacks a block the spec names or the spec has no land biome.
  SpecGenerator(this.spec, Map<String, int> ids, this.seed) : _ids = ids {
    if (spec.biomes.isEmpty) throw ArgumentError.value(spec.biomes, 'biomes', 'a world needs at least one land biome');
    for (final name in spec.blockNames) {
      _id(name);
    }
    _stone = _id(spec.stone);
    _water = _id(spec.water);
    _bedrock = spec.bedrock == null ? _stone : _id(spec.bedrock!);
    _land = [for (final b in spec.biomes) _compileBiome(b)];
    _ocean = spec.ocean == null ? null : _compileBiome(spec.ocean!);
    _beach = spec.beach == null ? null : _compileBiome(spec.beach!);
    var upTo = 0;
    _ores = OreTable([
      for (final o in spec.ores) OreVein(_id(o.block), belowY: o.belowY, upTo: upTo += (o.share * 10000).round()),
    ]);
    _lava = spec.caves.lava == null ? 0 : _id(spec.caves.lava!);
    _soft = {
      for (final b in [..._land, ?_ocean, ?_beach])
        for (final t in b.trees) ...[t.blocks.leaves, if (t.blocks.vines != 0) t.blocks.vines],
    };
    _canvas = TreeCanvas(isSoft: _soft.contains, groundAt: surfaceHeight, floorY: spec.seaLevel, hash: hash);
    for (var i = 0; i < spec.structures.length; i++) {
      final s = spec.structures[i];
      final grid = StructureGrid(regionChunks: s.regionChunks, primeX: 7919 + i * 104, salt: 200 + i, primeZ: 104729 + i * 97);
      assert(s.radius < grid.span ~/ 2, 'structure ${s.name} reaches past its region');
      _structures.add((spec: s, grid: grid));
      _byName[s.name] = s;
    }
    final t = spec.terrain;
    _continental = simplexNoise(seed, 0.0016 / t.scale, 3);
    _hills = simplexNoise(seed ^ 0x1234567, 0.0055 / t.scale, 3);
    _mountainMask = simplexNoise(seed ^ 0x2345678, 0.0028 / t.scale, 2);
    _ridge = simplexNoise(seed ^ 0x3456789, 0.014 / t.scale, 3, FractalType.ridged);
    _temperature = simplexNoise(seed ^ 0x456789A, 0.0020 / t.scale, 2);
    _humidity = simplexNoise(seed ^ 0x56789AB, 0.0024 / t.scale, 2);
    _river = simplexNoise(seed ^ 0x9ABCDEF, 0.0030 / t.scale, 2);
    _caves = CaveCarver(
      cave: simplexNoise(seed ^ 0x6789ABC, 0.050, 2),
      cavern: simplexNoise(seed ^ 0x789ABCD, 0.020, 2),
      seaLevel: spec.seaLevel,
    );
  }

  /// What is generated.
  final WorldGenSpec spec;

  /// The world seed.
  final int seed;

  final Map<String, int> _ids;
  late final int _stone, _water, _bedrock, _lava;
  late final List<_Biome> _land;
  late final _Biome? _ocean, _beach;
  late final OreTable _ores;
  late final Set<int> _soft;
  late final TreeCanvas _canvas;
  late final CaveCarver _caves;
  late final FastNoiseLite _continental, _hills, _mountainMask, _ridge, _temperature, _humidity, _river;
  final List<({StructureSpec spec, StructureGrid grid})> _structures = [];
  final Map<String, StructureSpec> _byName = {};

  static const ScatterGrid _treeGrid = ScatterGrid(patch: 7, inset: 2, salt: 91);

  /// How far outside a chunk a tree may stand and still reach into it.
  static const int _treeReach = 6;

  int _id(String name) {
    final id = _ids[name];
    if (id == null) throw ArgumentError.value(name, 'block', 'not in the game\'s block ids');
    return id;
  }

  _Biome _compileBiome(Biome b) {
    var plantUpTo = 0;
    return _Biome(
      b,
      top: _id(b.top),
      under: _id(b.under),
      ice: b.ice == null ? 0 : _id(b.ice!),
      trees: [
        for (final t in b.trees)
          (
            spec: t,
            blocks: TreeBlocks(log: _id(t.log), leaves: _id(t.leaves), vines: t.vines == null ? 0 : _id(t.vines!)),
          ),
      ],
      plants: [for (final p in b.plants) (block: _id(p.block), upTo: plantUpTo += p.perMille, height: p.height)],
    );
  }

  /// The world's positional hash under [seed].
  int hash(int x, int y, int z) => worldHash(seed, x, y, z);

  /// The first air cell above the ground of column ([x], [z]).
  int surfaceHeight(int x, int z) {
    final t = spec.terrain;
    final flat = t.flatHeight;
    if (flat != null) return flat;
    final xd = x.toDouble(), zd = z.toDouble();
    final land = smoothstep(-0.35, 0.15, _continental.getNoise2(xd, zd));
    var h = lerpd(t.lowland, t.highland, land);
    h += _hills.getNoise2(xd, zd) * (t.coastHills + (t.hills - t.coastHills) * land);
    final m = math.max(0.0, _mountainMask.getNoise2(xd, zd) - 0.25) / 0.75 * land;
    if (m > 0) h += m * (t.mountainBase + (_ridge.getNoise2(xd, zd) + 1.0) * 0.5 * t.mountainRidge);
    if (t.rivers) {
      final sea = spec.seaLevel;
      final rv = _river.getNoise2(xd, zd).abs();
      if (rv < 0.045 && h > sea - 3 && h < sea + 34) {
        final k = rv / 0.045;
        h = lerpd(sea - 3 + k * k * 2.0, h, k * k * k);
      }
    }
    return h.toInt().clamp(6, ChunkSize.sizeY - 6);
  }

  _Biome _biomeFor(int x, int z, int h) {
    final sea = spec.seaLevel;
    if (h < sea - 2 && _ocean != null) return _ocean;
    if (h <= sea + 1 && _beach != null) return _beach;
    final xd = x.toDouble(), zd = z.toDouble();
    final t = _temperature.getNoise2(xd, zd) - math.max(0, h - 72) / 50.0;
    final hum = _humidity.getNoise2(xd, zd);
    for (final b in _land) {
      if (b.spec.climate.contains(t, hum, h)) return b;
    }
    return _land.last;
  }

  /// The biome of column ([x], [z]).
  Biome biomeAt(int x, int z) => _biomeFor(x, z, surfaceHeight(x, z)).spec;

  /// Whether the rock at ([x], [y], [z]) is carved into a cave.
  bool isCave(int x, int y, int z) => spec.caves.enabled && _caves.carved(x, y, z, surfaceHeight(x, z));

  /// The structures whose regions touch chunk ([chunkX], [chunkZ]).
  List<PlacedStructure> structuresNear(int chunkX, int chunkZ) => [
        for (final s in _structures)
          for (final (rx, rz) in s.grid.around(chunkX, chunkZ)) ?_site(s.spec, s.grid, rx, rz),
      ];

  PlacedStructure? _site(StructureSpec s, StructureGrid grid, int rx, int rz) {
    final h = grid.hashOf(seed, rx, rz);
    if ((h >> 16) % 10000 >= (s.chance * 10000).round()) return null;
    final span = grid.span;
    final margin = s.radius + 1;
    final sx = rx * span + margin + h % (span - 2 * margin);
    final sz = rz * span + margin + (h >> 8) % (span - 2 * margin);
    final surface = surfaceHeight(sx, sz);
    if (surface <= spec.seaLevel + 1) return null;
    final allowed = s.biomes;
    if (allowed != null && !allowed.contains(_biomeFor(sx, sz, surface).spec.name)) return null;
    return (name: s.name, x: sx, y: surface - s.depth, z: sz);
  }

  @override
  Uint8List generateIn(int chunkX, int chunkZ, int dimension) {
    final blocks = Uint8List(ChunkSize.volume);
    final w = ChunkWriter(blocks, chunkX, chunkZ);
    final sea = spec.seaLevel;
    for (var z = 0; z < ChunkSize.sizeZ; z++) {
      for (var x = 0; x < ChunkSize.sizeX; x++) {
        final wx = w.ox + x, wz = w.oz + z;
        final h = surfaceHeight(wx, wz);
        final biome = _biomeFor(wx, wz, h);
        final soil = h - 1 - biome.spec.underDepth;
        for (var y = 0; y < ChunkSize.sizeY; y++) {
          var id = 0;
          if (y == 0) {
            id = _bedrock;
          } else if (y < soil) {
            id = _ores.pick(y, hash(wx >> 1, y >> 1, wz >> 1), hash(wx, y, wz)) ?? _stone;
          } else if (y < h - 1) {
            id = biome.under;
          } else if (y == h - 1) {
            id = biome.top;
          } else if (y <= sea) {
            id = y == sea && biome.ice != 0 ? biome.ice : _water;
          }
          if (id != 0 && id != _bedrock && id != _water && id != biome.ice && y > 1 && spec.caves.enabled && _caves.carved(wx, y, wz, h)) {
            id = y <= spec.caves.lavaBelowY ? _lava : 0;
          }
          if (id != 0) blocks[ChunkSize.index(x, y, z)] = id;
        }
      }
    }
    final near = structuresNear(chunkX, chunkZ);
    _decorate(w, near);
    for (final s in _structures) {
      for (final (rx, rz) in s.grid.around(chunkX, chunkZ)) {
        final site = _site(s.spec, s.grid, rx, rz);
        if (site == null) continue;
        s.spec.build(StructureSite(
          name: site.name,
          x: site.x,
          y: site.y,
          z: site.z,
          seed: seed,
          writer: w,
          block: _id,
          surfaceAt: surfaceHeight,
        ));
      }
    }
    return blocks;
  }

  void _decorate(ChunkWriter w, List<PlacedStructure> near) {
    final sea = spec.seaLevel;
    for (var z = -_treeReach; z < ChunkSize.sizeZ + _treeReach; z++) {
      for (var x = -_treeReach; x < ChunkSize.sizeX + _treeReach; x++) {
        final inside = x >= 0 && x < ChunkSize.sizeX && z >= 0 && z < ChunkSize.sizeZ;
        final wx = w.ox + x, wz = w.oz + z;
        final patch = _treeGrid.spotOf(seed, wx, wz);
        final tree = patch.x == wx && patch.z == wz;
        if (!inside && !tree) continue;
        final h = surfaceHeight(wx, wz);
        if (h <= sea) continue; // nothing grows under the sea
        final biome = _biomeFor(wx, wz, h);
        if (tree &&
            biome.trees.isNotEmpty &&
            patch.hash % 100 < biome.spec.treeChance &&
            !(spec.caves.enabled && _caves.carved(wx, h - 1, wz, h)) &&
            !_nearStructure(near, wx, wz)) {
          final t = biome.trees[(patch.hash >> 20) % biome.trees.length];
          final tall = t.spec.minHeight + (patch.hash >> 12) % (t.spec.maxHeight - t.spec.minHeight + 1);
          _canvas.begin(wx, h, wz);
          _drawTree(t.spec.shape, wx, h, wz, tall, patch.hash, t.blocks);
          _canvas.print(w);
        }
        if (!inside || w.blocks[ChunkSize.index(x, h - 1, z)] == 0) continue;
        final roll = hash(wx, 7, wz) % 1000;
        for (final p in biome.plants) {
          if (roll >= p.upTo) continue;
          for (var i = 0; i < p.height; i++) {
            w.place(x, h + i, z, p.block, over: _soft.contains);
          }
          break;
        }
      }
    }
  }

  bool _nearStructure(List<PlacedStructure> near, int wx, int wz) {
    for (final s in near) {
      final spec = _byName[s.name]!;
      if (spec.depth != 0) continue; // dug under the trees, never through them
      final r = spec.radius + _treeReach;
      final dx = s.x - wx, dz = s.z - wz;
      if (dx * dx + dz * dz <= r * r) return true;
    }
    return false;
  }

  void _drawTree(TreeShape shape, int x, int y, int z, int tall, int hsh, TreeBlocks b) {
    switch (shape) {
      case TreeShape.oak:
        Trees.oak(_canvas, x, y, z, tall, hsh, b);
      case TreeShape.bigOak:
        Trees.bigOak(_canvas, x, y, z, tall, hsh, b);
      case TreeShape.spruce:
        Trees.spruce(_canvas, x, y, z, tall, b);
      case TreeShape.willow:
        Trees.willow(_canvas, x, y, z, tall, hsh, b);
      case TreeShape.jungle:
        Trees.jungle(_canvas, x, y, z, tall, hsh, b);
      case TreeShape.palm:
        Trees.palm(_canvas, x, y, z, tall, hsh, b);
    }
  }
}

class _Biome {
  _Biome(this.spec, {required this.top, required this.under, required this.ice, required this.trees, required this.plants});

  final Biome spec;
  final int top, under, ice;
  final List<({TreeSpec spec, TreeBlocks blocks})> trees;
  final List<({int block, int upTo, int height})> plants;
}
