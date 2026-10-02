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
    final cavern = spec.cavern;
    if (cavern != null) {
      if (spec.caves.enabled) throw ArgumentError.value(spec.caves, 'caves', 'a cavern is open already: CaveSpec.none');
      for (final b in [...spec.biomes, ?spec.ocean, ?spec.beach]) {
        if (b.trees.isNotEmpty) throw ArgumentError.value(b.name, 'biomes', 'a cavern grows no trees');
        if (b.pools != null) throw ArgumentError.value(b.name, 'biomes', 'a cavern holds no pools');
        if (b.plants.any((p) => p.spread != 0 || p.byWater)) {
          throw ArgumentError.value(b.name, 'biomes', 'a cavern\'s plants neither spread nor seek water');
        }
      }
      if (cavern.roof >= ChunkSize.sizeY - 1) {
        throw ArgumentError.value(cavern.roof, 'cavern.roof', 'the roof must be under the top of the world');
      }
    }
    for (final name in spec.blockNames) {
      _id(name);
    }
    _stone = _id(spec.stone);
    _water = _id(spec.water);
    _bedrock = spec.bedrock == null ? _stone : _id(spec.bedrock!);
    _rock = Uint8List(ChunkSize.sizeY);
    for (var y = 0; y < ChunkSize.sizeY; y++) {
      _rock[y] = _stone;
      for (final s in spec.strata) {
        if (y < s.belowY) {
          _rock[y] = _id(s.block);
          break;
        }
      }
    }
    _land = [for (final b in spec.biomes) _compileBiome(b)];
    _ocean = spec.ocean == null ? null : _compileBiome(spec.ocean!);
    _beach = spec.beach == null ? null : _compileBiome(spec.beach!);
    var upTo = 0;
    _ores = OreTable([
      for (final o in spec.ores) OreVein(_id(o.block), belowY: o.belowY, upTo: upTo += (o.share * 10000).round()),
    ]);
    _lava = spec.caves.lava == null ? 0 : _id(spec.caves.lava!);
    _rockIds = {_stone, for (final s in spec.strata) _id(s.block), for (final o in spec.ores) _id(o.block)};
    _liquidIds = {_water, if (_lava != 0) _lava};
    _spreads = [..._land, ?_ocean, ?_beach].any((b) => b.plants.any((p) => p.spec.spread != 0));
    _soft = {
      for (final b in [..._land, ?_ocean, ?_beach])
        for (final t in b.trees) ...[t.blocks.leaves, if (t.blocks.vines != 0) t.blocks.vines],
    };
    _canvas = TreeCanvas(isSoft: _soft.contains, groundAt: surfaceHeight, floorY: spec.seaLevel, hash: hash);
    for (var i = 0; i < spec.structures.length; i++) {
      final s = spec.structures[i];
      final grid = StructureGrid(
        regionChunks: s.regionChunks,
        primeX: 7919 + i * 104,
        salt: 200 + i,
        primeZ: 104729 + i * 97,
      );
      assert(s.structure.radius < grid.span ~/ 2, 'structure ${s.name} reaches past its region');
      if (_byName.containsKey(s.name)) throw ArgumentError.value(s.name, 'structures', 'two structures share a name');
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
    var hangUpTo = 0;
    _hangs = [
      for (final p in cavern?.hangs ?? const <Plant>[])
        (block: _id(p.block), upTo: hangUpTo += p.perMille, height: p.height),
    ];
    if (cavern != null) _slab = simplexNoise(seed ^ 0x0A1B2C3, 0.030 / cavern.scale, 2);
  }

  /// What is generated.
  final WorldGenSpec spec;

  /// The world seed.
  final int seed;

  final Map<String, int> _ids;
  late final int _stone, _water, _bedrock, _lava;
  late final Uint8List _rock;
  late final Set<int> _rockIds, _liquidIds;
  late final bool _spreads;
  late final List<_Biome> _land;
  late final _Biome? _ocean, _beach;
  late final OreTable _ores;
  late final Set<int> _soft;
  late final TreeCanvas _canvas;
  late final CaveCarver _caves;
  late final FastNoiseLite _continental, _hills, _mountainMask, _ridge, _temperature, _humidity, _river;
  late final FastNoiseLite _slab;
  late final List<({int block, int upTo, int height})> _hangs;
  final List<({StructureSpec spec, StructureGrid grid})> _structures = [];
  final Map<String, StructureSpec> _byName = {};

  /// Structure candidates already rolled, by structure and region: a site
  /// checks every earlier structure's around it, and every chunk asks again.
  /// Cleared when it grows past [_candidatesKept].
  final Map<(int, int, int), PlacedStructure?> _candidates = {};
  static const int _candidatesKept = 4096;

  static const ScatterGrid _treeGrid = ScatterGrid(patch: 7, inset: 2, salt: 91);

  /// The four neighbours of a column, in the order a plant spreads.
  static const List<(int, int)> _sides = [(1, 0), (0, 1), (-1, 0), (0, -1)];

  /// How far outside a chunk a tree may stand and still reach into it.
  static const int _treeReach = 6;

  int _id(String name) {
    final id = _ids[name];
    if (id == null) throw ArgumentError.value(name, 'block', 'not in the game\'s block ids');
    return id;
  }

  _Biome _compileBiome(Biome b) {
    final pools = b.pools;
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
      plants: [for (final p in b.plants) (spec: p, block: _id(p.block))],
      covers: [for (final c in b.covers) (spec: c, block: _id(c.block))],
      pools: pools == null
          ? null
          : (spec: pools, bed: _id(pools.bed), noise: simplexNoise(seed ^ 0x89ABCDE, 0.09 / pools.scale, 1)),
    );
  }

  /// The world's positional hash under [seed].
  int hash(int x, int y, int z) => worldHash(seed, x, y, z);

  /// The first air cell above the ground of column ([x], [z]). In a cavern,
  /// the lowest floor above the sea: the first open cell over rock there, or
  /// just above the sea when the column has none.
  int surfaceHeight(int x, int z) {
    if (spec.cavern != null) return _cavernFloor(_cavernColumn(x, z, List<bool>.filled(ChunkSize.sizeY, false)));
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
    for (var i = 0; i < _structures.length; i++)
      for (final (rx, rz) in _structures[i].grid.around(chunkX, chunkZ)) ?_site(i, rx, rz),
  ];

  /// Structure [i]'s site in region ([rx], [rz]), or null: none rolled there,
  /// or one within reach of an earlier structure's candidate.
  PlacedStructure? _site(int i, int rx, int rz) {
    final site = _candidate(i, rx, rz);
    if (site == null) return null;
    final reach = _structures[i].spec.structure.radius;
    for (var j = 0; j < i; j++) {
      final other = _structures[j];
      final d = reach + other.spec.structure.radius;
      final span = other.grid.span;
      for (var oz = floorDiv(site.z - d, span); oz <= floorDiv(site.z + d, span); oz++) {
        for (var ox = floorDiv(site.x - d, span); ox <= floorDiv(site.x + d, span); ox++) {
          final o = _candidate(j, ox, oz);
          if (o != null && (o.x - site.x).abs() <= d && (o.z - site.z).abs() <= d) return null;
        }
      }
    }
    return site;
  }

  /// Structure [i]'s candidate in region ([rx], [rz]): rolled by the region's
  /// hash, on land, on one of its biomes; earlier structures not asked.
  PlacedStructure? _candidate(int i, int rx, int rz) {
    final key = (i, rx, rz);
    if (_candidates.containsKey(key)) return _candidates[key];
    if (_candidates.length >= _candidatesKept) _candidates.clear();
    return _candidates[key] = _roll(_structures[i].spec, _structures[i].grid, rx, rz);
  }

  PlacedStructure? _roll(StructureSpec s, StructureGrid grid, int rx, int rz) {
    final h = grid.hashOf(seed, rx, rz);
    if ((h >> 16) % 10000 >= (s.chance * 10000).round()) return null;
    final span = grid.span;
    final margin = s.structure.radius + 1;
    final sx = rx * span + margin + h % (span - 2 * margin);
    final sz = rz * span + margin + (h >> 8) % (span - 2 * margin);
    final surface = surfaceHeight(sx, sz);
    if (surface <= spec.seaLevel + 1) return null;
    final allowed = s.biomes;
    if (allowed != null && !allowed.contains(_biomeFor(sx, sz, surface).spec.name)) return null;
    return (name: s.name, x: sx, y: surface - s.structure.depth, z: sz);
  }

  /// Whether ([x], [y], [z]) of a cavern is open: between floor and roof,
  /// where the noise is over the threshold, the slab kept solid near both.
  bool _cavernOpen(int x, int y, int z) {
    final c = spec.cavern!;
    if (y <= c.floor || y >= c.roof) return false;
    final n = _slab.getNoise3(x.toDouble(), y * 1.4, z.toDouble());
    var edge = 0.0;
    if (y < c.floor + 6) edge = (c.floor + 6 - y) / 6.0;
    if (y > c.roof - 8) edge = math.max(edge, (y - (c.roof - 8)) / 8.0);
    return n - edge * 0.6 > c.threshold;
  }

  /// Fills [open] with which cells of cavern column ([x], [z]) are open.
  List<bool> _cavernColumn(int x, int z, List<bool> open) {
    for (var y = 0; y < ChunkSize.sizeY; y++) {
      open[y] = _cavernOpen(x, y, z);
    }
    return open;
  }

  /// The lowest floor above the sea in a cavern column [open].
  int _cavernFloor(List<bool> open) {
    final c = spec.cavern!;
    for (var y = math.max(spec.seaLevel + 1, c.floor + 1); y < c.roof; y++) {
      if (open[y] && !open[y - 1]) return y;
    }
    return spec.seaLevel + 1;
  }

  /// [dimension] is a router's ([DimensionGenerator]): one spec is one
  /// dimension.
  @override
  Uint8List generateIn(int chunkX, int chunkZ, int dimension) {
    final blocks = Uint8List(ChunkSize.volume);
    final w = ChunkWriter(blocks, chunkX, chunkZ);
    if (spec.cavern != null) {
      _cavern(w);
    } else {
      final columns = _Columns(this, w.ox, w.oz);
      _surface(w, columns);
      _decorate(w, columns, structuresNear(chunkX, chunkZ));
    }
    for (var i = 0; i < _structures.length; i++) {
      final s = _structures[i];
      for (final (rx, rz) in s.grid.around(chunkX, chunkZ)) {
        final site = _site(i, rx, rz);
        if (site == null) continue;
        s.spec.structure.build(
          StructureSite(
            name: site.name,
            x: site.x,
            y: site.y,
            z: site.z,
            seed: seed,
            writer: w,
            block: _id,
            surfaceAt: surfaceHeight,
            isRock: _rockIds.contains,
            isLiquid: _liquidIds.contains,
          ),
        );
      }
    }
    return blocks;
  }

  /// The columns of a cavern: bedrock at y 0, the floor and the roof, rock
  /// and its ores between, the sea in the open cells up to its level, each
  /// floor its biome's top over its under, with its plants, and what hangs
  /// from the ceilings.
  void _cavern(ChunkWriter w) {
    final c = spec.cavern!;
    final sea = spec.seaLevel;
    final blocks = w.blocks;
    final open = List<bool>.filled(ChunkSize.sizeY, false);
    for (var z = 0; z < ChunkSize.sizeZ; z++) {
      for (var x = 0; x < ChunkSize.sizeX; x++) {
        final wx = w.ox + x, wz = w.oz + z;
        _cavernColumn(wx, wz, open);
        final biome = _biomeFor(wx, wz, _cavernFloor(open));
        for (var y = 0; y <= c.roof; y++) {
          final int id;
          if (y == 0 || y == c.floor || y == c.roof) {
            id = _bedrock;
          } else if (open[y]) {
            id = y <= sea ? _water : 0;
          } else {
            id = _ores.pick(y, hash(wx >> 1, y >> 1, wz >> 1), hash(wx, y, wz)) ?? _rock[y];
          }
          if (id != 0) blocks[ChunkSize.index(x, y, z)] = id;
        }
        for (var y = math.max(sea, c.floor + 1); y < c.roof - 1; y++) {
          if (open[y] || !open[y + 1]) continue;
          // A floor: its biome's top over its under, and maybe a plant on it.
          blocks[ChunkSize.index(x, y, z)] = _topAt(biome, wx, wz, y + 1);
          for (var k = 1; k <= biome.spec.underDepth && y - k > c.floor && !open[y - k]; k++) {
            blocks[ChunkSize.index(x, y - k, z)] = biome.under;
          }
          final roll = hash(wx, y + 7, wz);
          var upTo = 0;
          for (final p in biome.plants) {
            upTo += p.spec.perMille;
            if (roll % 1000 >= upTo) continue;
            final tall = _tall(p.spec, roll);
            for (var i = 1; i <= tall && open[y + i] && y + i < c.roof; i++) {
              blocks[ChunkSize.index(x, y + i, z)] = p.block;
            }
            break;
          }
        }
        for (var y = c.roof - 1; y > sea + 1; y--) {
          if (open[y] || !open[y - 1]) continue;
          // A ceiling: something may hang from it.
          final roll = hash(wx, y ^ 0x55, wz) % 1000;
          for (final h in _hangs) {
            if (roll >= h.upTo) continue;
            for (var i = 1; i <= h.height && open[y - i] && y - i > sea; i++) {
              blocks[ChunkSize.index(x, y - i, z)] = h.block;
            }
            break;
          }
        }
      }
    }
  }

  /// The columns of an open-sky world: bedrock, rock (by stratum) and its
  /// ores, soil, the biome's top or cover, a pool's water over its bed, the
  /// sea, and the caves carved through.
  void _surface(ChunkWriter w, _Columns columns) {
    final blocks = w.blocks;
    final sea = spec.seaLevel;
    for (var z = 0; z < ChunkSize.sizeZ; z++) {
      for (var x = 0; x < ChunkSize.sizeX; x++) {
        final wx = w.ox + x, wz = w.oz + z;
        final h = columns.height(wx, wz);
        final biome = columns.biome(wx, wz);
        final pool = biome.pools != null && columns.pool(wx, wz);
        final top = pool ? _water : _topAt(biome, wx, wz, h);
        final soil = h - 1 - biome.spec.underDepth;
        for (var y = 0; y < ChunkSize.sizeY; y++) {
          var id = 0;
          if (y == 0) {
            id = _bedrock;
          } else if (pool && y == h - 2) {
            id = biome.pools!.bed;
          } else if (y < soil) {
            id = _ores.pick(y, hash(wx >> 1, y >> 1, wz >> 1), hash(wx, y, wz)) ?? _rock[y];
          } else if (y < h - 1) {
            id = biome.under;
          } else if (y == h - 1) {
            id = top;
          } else if (y <= sea) {
            id = y == sea && biome.ice != 0 ? biome.ice : _water;
          }
          if (id != 0 &&
              id != _bedrock &&
              id != _water &&
              id != biome.ice &&
              y > 1 &&
              spec.caves.enabled &&
              _caves.carved(wx, y, wz, h)) {
            id = y <= spec.caves.lavaBelowY ? _lava : 0;
          }
          if (id != 0) blocks[ChunkSize.index(x, y, z)] = id;
        }
      }
    }
  }

  /// The surface block of [b]'s column ([wx], [wz]) with surface height [h]:
  /// the first cover whose window holds [h] and whose roll hits, or its top.
  int _topAt(_Biome b, int wx, int wz, int h) {
    for (var i = 0; i < b.covers.length; i++) {
      final c = b.covers[i].spec;
      if ((c.minHeight != null && h < c.minHeight!) || (c.maxHeight != null && h > c.maxHeight!)) continue;
      if (c.perMille < 1000 && hash(floorDiv(wx, c.patch), 0x3C0 + i, floorDiv(wz, c.patch)) % 1000 >= c.perMille) {
        continue;
      }
      return b.covers[i].block;
    }
    return b.top;
  }

  /// Whether column ([wx], [wz]) of [columns] is a pool: its biome has pools,
  /// it stands above the sea where the pool noise runs high, no neighbour
  /// stands lower and no cave opens under the bed or beside the water.
  bool _isPool(_Columns columns, int wx, int wz) {
    final pools = columns.biome(wx, wz).pools;
    if (pools == null) return false;
    final h = columns.height(wx, wz);
    if (h <= spec.seaLevel) return false;
    if (pools.noise.getNoise2(wx.toDouble(), wz.toDouble()) <= pools.spec.threshold) return false;
    final caves = spec.caves.enabled;
    if (caves && _caves.carved(wx, h - 2, wz, h)) return false;
    for (final (dx, dz) in _sides) {
      final nh = columns.height(wx + dx, wz + dz);
      if (nh < h) return false;
      if (caves && _caves.carved(wx + dx, h - 1, wz + dz, nh)) return false;
    }
    return true;
  }

  /// Whether a neighbour of column ([wx], [wz]), ground [h], is water at the
  /// surface no more than a block under its ground: the sea, a river, a pool.
  bool _byWater(_Columns columns, int wx, int wz, int h) {
    final sea = spec.seaLevel;
    for (final (dx, dz) in _sides) {
      final nx = wx + dx, nz = wz + dz;
      final nh = columns.height(nx, nz);
      final water = nh <= sea ? sea : (columns.pool(nx, nz) ? nh - 1 : -1);
      if (water >= h - 2) return true;
    }
    return false;
  }

  /// Whether the ground block of column ([wx], [wz]), surface [h], is carved
  /// away to air: what `_surface` does to it, asked of the position alone.
  bool _groundGone(int wx, int h, int wz) {
    final y = h - 1;
    if (y <= 1 || !spec.caves.enabled || !_caves.carved(wx, y, wz, h)) return false;
    return y > spec.caves.lavaBelowY || _lava == 0;
  }

  void _decorate(ChunkWriter w, _Columns columns, List<PlacedStructure> near) {
    final sea = spec.seaLevel;
    for (var z = -_treeReach; z < ChunkSize.sizeZ + _treeReach; z++) {
      for (var x = -_treeReach; x < ChunkSize.sizeX + _treeReach; x++) {
        final inside = x >= 0 && x < ChunkSize.sizeX && z >= 0 && z < ChunkSize.sizeZ;
        // A plant that spreads may reach in from the ring just outside.
        final plants = inside || (_spreads && x >= -1 && x <= ChunkSize.sizeX && z >= -1 && z <= ChunkSize.sizeZ);
        final wx = w.ox + x, wz = w.oz + z;
        final patch = _treeGrid.spotOf(seed, wx, wz);
        final tree = patch.x == wx && patch.z == wz;
        if (!plants && !tree) continue;
        final h = columns.height(wx, wz);
        if (h <= sea) continue; // nothing grows under the sea
        final biome = columns.biome(wx, wz);
        final pool = biome.pools != null && columns.pool(wx, wz);
        if (tree &&
            biome.trees.isNotEmpty &&
            patch.hash % 100 < biome.spec.treeChance &&
            !pool &&
            !(spec.caves.enabled && _caves.carved(wx, h - 1, wz, h)) &&
            !_nearStructure(near, wx, wz)) {
          final t = _pickTree(biome, patch.hash >> 20);
          final below = t.spec.belowY;
          if (below == null || h < below) {
            final tall = t.spec.minHeight + (patch.hash >> 12) % (t.spec.maxHeight - t.spec.minHeight + 1);
            _canvas.begin(wx, h, wz);
            _drawTree(t.spec.shape, wx, h, wz, tall, patch.hash, t.blocks);
            _canvas.print(w);
          }
        }
        if (!plants || pool) continue; // nothing grows in a pool
        if (inside ? w.blocks[ChunkSize.index(x, h - 1, z)] == 0 : _groundGone(wx, h, wz)) continue;
        _plant(w, columns, x, h, z, wx, wz, biome);
      }
    }
  }

  /// The plant of column ([wx], [wz]), chunk-local ([x], [z]), on ground
  /// [h]: one roll, its biome's plants tried in order, a plant that seeks
  /// water skipped away from it, and a spreading one grown on the
  /// neighbours level with it too.
  void _plant(ChunkWriter w, _Columns columns, int x, int h, int z, int wx, int wz, _Biome biome) {
    final roll = hash(wx, 7, wz);
    var upTo = 0;
    for (final p in biome.plants) {
      final s = p.spec;
      if (s.byWater && !_byWater(columns, wx, wz, h)) continue;
      upTo += s.perMille;
      if (roll % 1000 >= upTo) continue;
      final tall = _tall(s, roll);
      _stand(w, x, h, z, p.block, tall);
      for (var k = 0; k < s.spread; k++) {
        if ((roll >> (14 + k)) & 1 != 0) continue;
        final (dx, dz) = _sides[k];
        final nx = wx + dx, nz = wz + dz;
        if (columns.height(nx, nz) != h || columns.pool(nx, nz) || _groundGone(nx, h, nz)) continue;
        _stand(w, x + dx, h, z + dz, p.block, tall);
      }
      break;
    }
  }

  /// How tall plant [s] stands for [roll].
  static int _tall(Plant s, int roll) =>
      s.maxHeight == s.height ? s.height : s.height + (roll >> 10) % (s.maxHeight - s.height + 1);

  /// A plant [tall] blocks high at chunk-local ([x], [h], [z]), over air or a
  /// canopy.
  void _stand(ChunkWriter w, int x, int h, int z, int block, int tall) {
    for (var i = 0; i < tall; i++) {
      w.place(x, h + i, z, block, over: _soft.contains);
    }
  }

  /// The tree of [b] that [roll] picks, by weight.
  static ({TreeSpec spec, TreeBlocks blocks}) _pickTree(_Biome b, int roll) {
    var r = roll % b.treeWeight;
    for (final t in b.trees) {
      r -= t.spec.weight;
      if (r < 0) return t;
    }
    throw StateError('a roll under the total weight picks a tree');
  }

  bool _nearStructure(List<PlacedStructure> near, int wx, int wz) {
    for (final s in near) {
      final clearing = _byName[s.name]!.structure.clearing;
      if (clearing == 0) continue; // dug under the trees, never through them
      final r = clearing + _treeReach;
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
  _Biome(
    this.spec, {
    required this.top,
    required this.under,
    required this.ice,
    required this.trees,
    required this.plants,
    required this.covers,
    required this.pools,
  }) : treeWeight = trees.fold(0, (sum, t) => sum + t.spec.weight);

  final Biome spec;
  final int top, under, ice;
  final List<({TreeSpec spec, TreeBlocks blocks})> trees;
  final int treeWeight;
  final List<({Plant spec, int block})> plants;
  final List<({Cover spec, int block})> covers;
  final ({Pools spec, int bed, FastNoiseLite noise})? pools;
}

/// The heights and biomes of one chunk's columns and a ring around them,
/// each worked out once (the surface, the plants and the pools all ask), and
/// which of them are pools, asked lazily. A column past the ring is worked
/// out every time it is asked.
class _Columns {
  _Columns(this._g, this.ox, this.oz) {
    for (var z = 0; z < _sideZ; z++) {
      for (var x = 0; x < _sideX; x++) {
        final wx = ox - _ring + x, wz = oz - _ring + z;
        final h = _g.surfaceHeight(wx, wz);
        _heights[z * _sideX + x] = h;
        _biomes.add(_g._biomeFor(wx, wz, h));
      }
    }
  }

  static const int _ring = 2;
  static const int _sideX = ChunkSize.sizeX + 2 * _ring, _sideZ = ChunkSize.sizeZ + 2 * _ring;

  final SpecGenerator _g;

  /// World x and z of the chunk's first column.
  final int ox, oz;

  final Int32List _heights = Int32List(_sideX * _sideZ);
  final List<_Biome> _biomes = [];

  /// 0 not asked yet, 1 dry, 2 a pool.
  final Uint8List _pools = Uint8List(_sideX * _sideZ);

  int _index(int wx, int wz) {
    final x = wx - ox + _ring, z = wz - oz + _ring;
    if (x < 0 || x >= _sideX || z < 0 || z >= _sideZ) return -1;
    return z * _sideX + x;
  }

  /// The surface height of column ([wx], [wz]).
  int height(int wx, int wz) {
    final i = _index(wx, wz);
    return i < 0 ? _g.surfaceHeight(wx, wz) : _heights[i];
  }

  /// The biome of column ([wx], [wz]).
  _Biome biome(int wx, int wz) {
    final i = _index(wx, wz);
    return i < 0 ? _g._biomeFor(wx, wz, _g.surfaceHeight(wx, wz)) : _biomes[i];
  }

  /// Whether column ([wx], [wz]) is a pool.
  bool pool(int wx, int wz) {
    final i = _index(wx, wz);
    if (i < 0) return _g._isPool(this, wx, wz);
    if (_pools[i] == 0) _pools[i] = _g._isPool(this, wx, wz) ? 2 : 1;
    return _pools[i] == 2;
  }
}
