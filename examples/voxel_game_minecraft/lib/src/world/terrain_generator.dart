import 'dart:math' as math;
import 'dart:typed_data';

import 'package:voxel_engine/worldgen.dart';

import 'package:voxel_engine/core.dart';

/// Pure (seed, position) terrain: biomes from temperature/humidity/continental
/// noise, a height field with hills and ridged mountains, 3D caves, ores by
/// depth, lava in the deep, and decorations (trees, cacti, plants) that can
/// cross chunk borders. Runs on worker isolates; nothing here touches the scene.
class TerrainGenerator implements ChunkGenerator {
  TerrainGenerator({required this.ids, required int seed, this.playground = false}) {
    _stone = ids['stone']!;
    _dirt = ids['dirt']!;
    _grass = ids['grass']!;
    _sand = ids['sand']!;
    _water = ids['water']!;
    _oakLog = ids['oak_log']!;
    _oakLeaves = ids['oak_leaves']!;
    _gravel = ids['gravel']!;
    _sandstone = ids['sandstone']!;
    _snow = ids['snow']!;
    _spruceLog = ids['spruce_log']!;
    _spruceLeaves = ids['spruce_leaves']!;
    _cactus = ids['cactus']!;
    _coalOre = ids['coal_ore']!;
    _ironOre = ids['iron_ore']!;
    _goldOre = ids['gold_ore']!;
    _diamondOre = ids['diamond_ore']!;
    _bedrock = ids['bedrock']!;
    _tallGrass = ids['tall_grass']!;
    _flowerRed = ids['flower_red']!;
    _flowerYellow = ids['flower_yellow']!;
    _lava = ids['lava']!;
    _clay = ids['clay']!;
    _deadBush = ids['dead_bush']!;
    _mushroom = ids['mushroom']!;
    _ice = ids['ice']!;
    _darkStone = ids['dark_stone']!;
    _mossyBricks = ids['mossy_stone_bricks']!;
    _stoneBricks = ids['stone_bricks']!;
    _chest = ids['chest']!;
    _lamp = ids['lamp']!;
    _boneBlock = ids['bone_block']!;
    _planks = ids['oak_planks']!;
    _ladderId = ids['ladder']!;
    _spawnerId = ids['spawner']!;
    _glassId = ids['glass']!;
    _craftingTable = ids['crafting_table']!;
    _furnace = ids['furnace']!;
    _torch = ids['torch']!;
    _fence = ids['oak_fence']!;
    _tnt = ids['tnt']!;
    _cobblestone = ids['cobblestone']!;
    _pressurePlate = ids['pressure_plate']!;
    _mud = ids['mud']!;
    _reeds = ids['reeds']!;
    _jungleLog = ids['jungle_log']!;
    _vines = ids['vines']!;
    _fern = ids['fern']!;
    _melon = ids['melon']!;
    _bed = ids['bed']!;
    _farmland = ids['farmland']!;
    _wheat = ids['wheat_2']!;
    _slab = ids['oak_slab']!;
    _redstoneOre = ids['redstone_ore']!;
    _railEw = ids['rail_ew']!;
    _hellstone = ids['hellstone']!;
    _soulSand = ids['soul_sand']!;
    _glowstone = ids['glowstone']!;
    _quartzOre = ids['nether_quartz_ore']!;
    _netherBrick = ids['nether_brick']!;
    _fortressCore = ids['fortress_core']!;
    // VK2.2: ores, trees and caves are voxel_worldgen's machinery, fed this
    // game's blocks and thresholds.
    _ores = OreTable([
      OreVein(_diamondOre, belowY: 14, upTo: 60),
      OreVein(_goldOre, belowY: 32, upTo: 200),
      OreVein(_ironOre, belowY: 64, upTo: 520),
      OreVein(_redstoneOre, belowY: 30, upTo: 710), // stage 27: about a third of coal's share, deep only
      OreVein(_coalOre, upTo: 1100),
    ]);
    _oakTree = TreeBlocks(log: _oakLog, leaves: _oakLeaves);
    _spruceTree = TreeBlocks(log: _spruceLog, leaves: _spruceLeaves);
    _jungleTree = TreeBlocks(log: _jungleLog, leaves: _oakLeaves, vines: _vines);
    _canvas = TreeCanvas(isSoft: _isSoft, groundAt: surfaceHeight, floorY: seaLevel, hash: hash);
    setSeed(seed);
  }

  static const int sizeX = ChunkSize.sizeX;
  static const int sizeZ = ChunkSize.sizeZ;
  static const int sizeY = ChunkSize.sizeY;
  static const int seaLevel = 46;
  static const int volume = ChunkSize.volume;

  static const int biomeOcean = 0,
      biomeBeach = 1,
      biomePlains = 2,
      biomeForest = 3,
      biomeDesert = 4,
      biomeSnow = 5,
      biomeMountain = 6,
      biomeSwamp = 7,
      biomeJungle = 8,
      biomeUnderworld = 9; // stage 29: the whole second dimension is one biome

  /// Stage 29: the dimension a chunk is generated for.
  static const int dimOverworld = 0, dimUnderworld = 1;
  int _dimension = dimOverworld;
  void setDimension(int d) => _dimension = d;
  int get dimension => _dimension;

  static const int structNone = 0, structDungeon = 1, structTower = 2, structCamp = 3, structVillage = 4;
  static const int structRuin = 5, structWell = 6, structMine = 7, structTemple = 8;

  /// Stage 33: a playground world flattens a plaza around the spawn: grass at
  /// [plazaFloor] (the feet level) over x/z in [plazaMin, plazaMax), no caves,
  /// trees or structures there, and the natural height eased back in over
  /// [plazaBlend] blocks outside it. The underworld is untouched.
  final bool playground;
  static const int plazaMin = -64, plazaMax = 80, plazaFloor = 64, plazaBlend = 16;

  /// Whether column ([x], [z]) is within [margin] blocks of the plaza.
  static bool inPlaza(int x, int z, [int margin = 0]) =>
      x >= plazaMin - margin && x < plazaMax + margin && z >= plazaMin - margin && z < plazaMax + margin;

  /// Blocks from column ([x], [z]) to the plaza's edge (0 inside).
  static int plazaDistance(int x, int z) {
    final dx = x < plazaMin ? plazaMin - x : (x >= plazaMax ? x - plazaMax + 1 : 0);
    final dz = z < plazaMin ? plazaMin - z : (z >= plazaMax ? z - plazaMax + 1 : 0);
    return math.max(dx, dz);
  }

  /// A structure a playground keeps out of the plaza (48 blocks clear, the
  /// size of the largest one).
  bool _structureAllowed(({int x, int y, int z, int type}) s) => !playground || !inPlaza(s.x, s.z, 48);

  static const int _air = 0;
  final Map<String, int> ids;
  late int _stone, _dirt, _grass, _sand, _water, _oakLog, _oakLeaves, _gravel, _sandstone, _snow,
      _spruceLog, _spruceLeaves, _cactus, _coalOre, _ironOre, _goldOre, _diamondOre, _bedrock,
      _tallGrass, _flowerRed, _flowerYellow, _lava, _clay, _deadBush, _mushroom, _ice, _darkStone,
      _mossyBricks, _stoneBricks, _chest, _lamp, _boneBlock, _planks, _ladderId, _spawnerId,
      _glassId, _craftingTable, _furnace, _torch, _fence, _tnt, _cobblestone, _pressurePlate,
      // Stage 26: the swamp's mud and reeds, the jungle's logs, vines, ferns and
      // melons, and what a village hut holds (bed, farmland + ripe wheat, the slab roof).
      _mud, _reeds, _jungleLog, _vines, _fern, _melon, _bed, _farmland, _wheat, _slab,
      // Stage 27: redstone ore, veined below y 30.
      _redstoneOre,
      // Stage 28: the rail down an abandoned mine's corridor.
      _railEw,
      // Stage 29: the underworld's blocks and the fortress bricks.
      _hellstone, _soulSand, _glowstone, _quartzOre, _netherBrick, _fortressCore;
  late final OreTable _ores;
  late final TreeBlocks _oakTree, _spruceTree, _jungleTree;
  late final TreeCanvas _canvas;
  late CaveCarver _caves;

  int _seed = 0;
  int get seed => _seed;
  late FastNoiseLite _continental, _hills, _mountainMask, _ridge, _temperature, _humidity, _detail, _river, _hell, _hellPatch;

  static const _make = simplexNoise;

  void setSeed(int seed) {
    _seed = seed;
    _continental = _make(seed, 0.0016, 3);
    _hills = _make(seed ^ 0x1234567, 0.0055, 3);
    _mountainMask = _make(seed ^ 0x2345678, 0.0028, 2);
    _ridge = _make(seed ^ 0x3456789, 0.014, 3, FractalType.ridged);
    _temperature = _make(seed ^ 0x456789A, 0.0020, 2);
    _humidity = _make(seed ^ 0x56789AB, 0.0024, 2);
    _caves = CaveCarver(cave: _make(seed ^ 0x6789ABC, 0.050, 2), cavern: _make(seed ^ 0x789ABCD, 0.020, 2), seaLevel: seaLevel);
    _detail = _make(seed ^ 0x89ABCDE, 0.06, 1); // stage 26: the swamp pools
    _river = _make(seed ^ 0x9ABCDEF, 0.0030, 2);
    _hell = _make(seed ^ 0x0A1B2C3, 0.030, 2); // stage 29: the underworld's caverns
    _hellPatch = _make(seed ^ 0x0B2C3D4, 0.070, 1); // soul sand patches on its floors
  }

  static int index(int x, int y, int z) => ChunkSize.index(x, y, z);

  static const _smooth = smoothstep;
  static const _lerp = lerpd;

  int surfaceHeight(int x, int z) {
    if (!playground) return _naturalHeight(x, z);
    final d = plazaDistance(x, z);
    if (d == 0) return plazaFloor;
    if (d >= plazaBlend) return _naturalHeight(x, z);
    return _lerp(plazaFloor.toDouble(), _naturalHeight(x, z).toDouble(), _smooth(0, plazaBlend.toDouble(), d.toDouble())).round();
  }

  int _naturalHeight(int x, int z) {
    final xd = x.toDouble(), zd = z.toDouble();
    final cont = _continental.getNoise2(xd, zd);
    final land = _smooth(-0.35, 0.15, cont);
    var h = _lerp(24, 54, land);
    h += _hills.getNoise2(xd, zd) * (4.0 + 7.0 * land);
    final m = ((_mountainMask.getNoise2(xd, zd) - 0.25).clamp(0.0, double.infinity)) / 0.75 * land;
    if (m > 0) {
      final r = (_ridge.getNoise2(xd, zd) + 1.0) * 0.5;
      h += m * (18.0 + r * 48.0);
    }
    // Rivers: a narrow band where a low-frequency noise crosses zero, carved to just below sea level.
    final rv = _river.getNoise2(xd, zd).abs();
    if (rv < 0.045 && h > seaLevel - 3 && h < 80) {
      final t = rv / 0.045;
      final bed = seaLevel - 3 + t * t * 2.0;
      h = _lerp(bed, h, t * t * t);
    }
    // Stage 26: a swamp is low and flat. Where the climate says swamp and the land
    // sits just above the sea, the hills are pressed down to a plain two blocks
    // over sea level.
    if (h >= seaLevel + 1 && h < seaLevel + 9 && _isSwampClimate(x, z)) {
      h = seaLevel + 2 + (h - seaLevel - 2) * 0.3;
    }
    return h.toInt().clamp(6, sizeY - 6);
  }

  bool _isSwampClimate(int x, int z) {
    final t = _temperature.getNoise2(x.toDouble(), z.toDouble());
    final hum = _humidity.getNoise2(x.toDouble(), z.toDouble());
    return hum > 0.42 && t > 0.1 && !(t > 0.30 && hum < 0.05);
  }

  /// A swamp column whose surface block is a one-deep pool (water over mud).
  bool _swampPool(int wx, int wz, int h, int biome) =>
      biome == biomeSwamp && h > seaLevel && _detail.getNoise2(wx * 1.5, wz * 1.5) > 0.28;

  int biomeAt(int x, int z) => _dimension == dimUnderworld ? biomeUnderworld : _biomeFor(x, z, surfaceHeight(x, z));

  int _biomeFor(int x, int z, int h) {
    if (playground && inPlaza(x, z)) return biomePlains; // stage 33: the plaza is grass
    if (h < seaLevel - 2) return biomeOcean;
    final t = _temperature.getNoise2(x.toDouble(), z.toDouble()) - ((h - 72).clamp(0, 1 << 30)) / 50.0;
    final hum = _humidity.getNoise2(x.toDouble(), z.toDouble());
    if (h > 86) return biomeMountain;
    if (h <= seaLevel + 1) return t < -0.4 ? biomeSnow : biomeBeach;
    if (t < -0.35) return biomeSnow;
    if (t > 0.30 && hum < 0.05) return biomeDesert;
    if (hum > 0.42 && t > 0.1 && h < seaLevel + 6) return biomeSwamp;
    if (t > 0.22 && hum > 0.28) return biomeJungle; // stage 26: hot and wet
    if (hum > 0.22) return biomeForest;
    return biomePlains;
  }

  int hash(int x, int y, int z) => worldHash(_seed, x, y, z);

  /// The chunk of the generator's current dimension ([setDimension]).
  Uint8List generate(int chunkX, int chunkZ) => generateIn(chunkX, chunkZ, _dimension);

  /// Stage 29: the chunk of an explicit dimension. The worker binds the
  /// dimension at dispatch, so a job started before a switch still writes what
  /// it was asked for.
  @override
  Uint8List generateIn(int chunkX, int chunkZ, int dimension) {
    if (dimension == dimUnderworld) return _generateUnderworld(chunkX, chunkZ);
    final blocks = Uint8List(volume);
    final ox = chunkX * sizeX, oz = chunkZ * sizeZ;
    for (var z = 0; z < sizeZ; z++) {
      for (var x = 0; x < sizeX; x++) {
        final wx = ox + x, wz = oz + z;
        final h = surfaceHeight(wx, wz);
        final biome = _biomeFor(wx, wz, h);
        for (var y = 0; y < sizeY; y++) {
          var id = _air;
          if (y == 0) {
            id = _bedrock;
          } else if (y < h - 4) {
            id = y < 22 ? _darkStone : _stone;
          } else if (y < h - 1) {
            id = biome == biomeDesert || biome == biomeBeach ? _sandstone : (biome == biomeMountain ? _stone : _dirt);
            if (y == h - 2 && biome == biomeSwamp && _swampPool(wx, wz, h, biome)) id = _mud; // the pool's bed
          } else if (y == h - 1) {
            switch (biome) {
              case biomeOcean:
                id = hash(wx, 0, wz) % 5 == 0 ? _gravel : (hash(wx, 1, wz) % 7 == 0 ? _clay : _sand);
              case biomeBeach:
              case biomeDesert:
                id = _sand;
              case biomeSnow:
                id = _snow;
              case biomeMountain:
                id = h > 100 ? _snow : (hash(wx, 2, wz) % 4 == 0 ? _gravel : _stone);
              case biomeSwamp:
                if (_swampPool(wx, wz, h, biome)) {
                  id = _water;
                } else {
                  id = hash(wx >> 1, 3, wz >> 1) % 5 < 2 ? _mud : (hash(wx, 3, wz) % 7 == 0 ? _clay : _grass);
                }
              default:
                id = _grass;
            }
          } else if (y <= seaLevel) {
            id = (biome == biomeSnow && y == seaLevel) ? _ice : _water;
          }

          // Ores replace stone: a 2x2x2 cell decides a vein, a block hash thins it.
          if (id == _stone || id == _darkStone) {
            id = _ores.pick(y, hash(wx >> 1, y >> 1, wz >> 1), hash(wx, y, wz)) ?? id;
          }

          // Caves: cheese caves everywhere in rock, caverns deeper, sealed near
          // the surface unless an entrance noise opens it.
          if (id != _air && id != _bedrock && id != _water && id != _ice && y > 1 && _carved(wx, y, wz, h)) {
            id = y <= 10 ? _lava : _air;
          }

          if (id != _air) blocks[index(x, y, z)] = id;
        }
      }
    }
    final w = ChunkWriter(blocks, chunkX, chunkZ);
    _decorate(w, structuresNearIn(chunkX, chunkZ, dimOverworld));
    _buildStructures(w);
    return blocks;
  }

  /// How far outside a chunk a tree may stand and still drop a leaf inside it:
  /// the widest crown (5) plus the far side of a 2x2 trunk (1).
  static const int _reach = 6;

  /// Stage 41: the tree grid. The world is cut into [_treePatch] squares and at
  /// most one tree grows in each, never closer than [_treeInset] to the patch
  /// border — so two trunks always stand `2 * _treeInset + 1` blocks apart.
  /// Trees used to be rolled per column, which let two of them touch and made a
  /// forest a wall; the patch is what puts a path between the trunks.
  static const int _treePatch = 7, _treeInset = 2;

  /// How many patches of a biome carry a tree, in per cent. Roughly a quarter
  /// of the old per-column rate, which is what doubles the gap between trunks.
  /// The beach is the exception: stage 42 keeps every tree out of the water, and
  /// the only dry beach column is the one row right on the waterline, so its
  /// share is raised to keep the palms it used to grow standing in the sea.
  static int treeChance(int biome) => switch (biome) {
        biomeForest => 92,
        biomeJungle => 47,
        biomeSnow => 37,
        biomeSwamp => 27,
        biomePlains => 20,
        biomeMountain => 20,
        biomeBeach => 30,
        biomeDesert => 8,
        _ => 0,
      };

  /// The column of the patch holding ([wx], [wz]) where its tree may grow, and
  /// the patch's hash. Pure position, so every chunk agrees on it; public so a
  /// test can walk the grid without generating a world.
  ({int x, int z, int hash}) treePatchOf(int wx, int wz) => _treeGrid.spotOf(_seed, wx, wz);

  static const ScatterGrid _treeGrid = ScatterGrid(patch: _treePatch, inset: _treeInset, salt: 91);

  /// Trees, cacti and plants. The small stuff belongs to this chunk's own
  /// columns; a tree is looked for over every column that can REACH this chunk,
  /// so a crown crossing a border arrives whole.
  void _decorate(ChunkWriter w, List<({int x, int y, int z, int type})> near) {
    final ox = w.ox, oz = w.oz;
    for (var z = -_reach; z < sizeZ + _reach; z++) {
      for (var x = -_reach; x < sizeX + _reach; x++) {
        final inside = x >= 0 && x < sizeX && z >= 0 && z < sizeZ;
        final wx = ox + x, wz = oz + z;
        // The patch is a hash and the height is noise, so the cheap question
        // goes first: a column outside the chunk matters only for its tree.
        final patch = treePatchOf(wx, wz);
        final tree = patch.x == wx && patch.z == wz;
        if (!inside && !tree) continue;
        if (playground && inPlaza(wx, wz, 8)) continue; // stage 33: nothing leans into the plaza
        final h = surfaceHeight(wx, wz);
        final biome = _biomeFor(wx, wz, h);
        final pool = biome == biomeSwamp && _swampPool(wx, wz, h, biome);
        if (tree && patch.hash % 100 < treeChance(biome) && !pool && _treeGround(wx, wz, h) && !_underStructure(near, wx, wz)) {
          _growTree(w, wx, h, wz, biome, patch.hash);
        }
        if (!inside || pool) continue; // nothing grows in a pool
        if (w.blocks[index(x, h - 1, z)] == _air) continue;
        _plantSmall(w, x, h, z, wx, wz, biome, hash(wx, 7, wz));
      }
    }
  }

  /// Stage 42: where a tree is allowed to put its foot. Dry land standing clear
  /// of the sea, with no cave mouth eating the very block it would stand on.
  /// The answer comes from the position alone — the chunk being filled has no
  /// say in it — so the two chunks a crown straddles always agree on whether
  /// the tree is there at all. While only the owning chunk could refuse, the
  /// other one still wrote its half of the crown, and that half hung in the
  /// air with no trunk anywhere under it.
  bool _treeGround(int wx, int wz, int h) {
    if (h <= seaLevel) return false; // a trunk standing in water is a tree floating on it
    return !_carved(wx, h - 1, wz, h);
  }

  /// The cave test of [generateIn] asked about one block: true where the rock at
  /// ([wx], [wy], [wz]) is carved away. Positional like everything else here, so
  /// a tree and a builder can both ask it about a column that is not theirs.
  bool _carved(int wx, int wy, int wz, int h) {
    if (playground && inPlaza(wx, wz, 2)) return false;
    return _caves.carved(wx, wy, wz, h);
  }

  /// Stage 42: how far around a structure no tree may root — what it writes
  /// inside of, widened by [_reach], the farthest any part of a tree ever stands
  /// from its own trunk. A builder runs after the trees and writes over whatever
  /// it lands on; when that was a trunk, everything above the cut stayed behind,
  /// hanging over the roof with nothing under it. Keeping the trees out is also
  /// what makes a village a clearing, with never a tree felled to get one.
  static int _structureClearance(int type) {
    final footprint = switch (type) {
      structVillage => _villageClearRadius,
      structCamp => 8,
      structRuin => 6,
      structTemple => 6,
      structTower => 4,
      structWell => 3,
      structMine => 3,
      _ => 0, // the dungeon is dug under the trees, never through them
    };
    return footprint == 0 ? 0 : footprint + _reach;
  }

  bool _underStructure(List<({int x, int y, int z, int type})> near, int wx, int wz) {
    for (final s in near) {
      final r = _structureClearance(s.type);
      if (r == 0) continue;
      final dx = s.x - wx, dz = s.z - wz;
      if (dx * dx + dz * dz <= r * r) return true;
    }
    return false;
  }

  // --- trees (stage 42; VK2.2: voxel_worldgen's TreeCanvas and Trees) -------------

  /// Leaves and vines: what a log may be drawn over, and what may never be
  /// drawn over anything.
  bool _isSoft(int id) => id == _oakLeaves || id == _spruceLeaves || id == _vines;

  /// Draws the biome's tree on the canvas and prints the part of it that holds
  /// together onto this chunk.
  void _growTree(ChunkWriter w, int wx, int y, int wz, int biome, int hsh) {
    _canvas.begin(wx, y, wz);
    _plantTree(wx, y, wz, biome, hsh);
    _canvas.print(w);
  }

  /// The tree this biome grows, planted on the canvas with its patch's [hsh].
  void _plantTree(int x, int y, int z, int biome, int hsh) {
    final tall = (hsh >> 12) % 5;
    switch (biome) {
      case biomeForest:
        if ((hsh >> 20) % 100 < 30) {
          Trees.bigOak(_canvas, x, y, z, 14 + tall, hsh, _oakTree);
        } else {
          Trees.oak(_canvas, x, y, z, 9 + tall % 4, hsh, _oakTree);
        }
      case biomePlains:
        Trees.oak(_canvas, x, y, z, 9 + tall % 4, hsh, _oakTree);
      case biomeSwamp:
        Trees.willow(_canvas, x, y, z, 9 + tall % 3, hsh, _oakTree);
      case biomeJungle:
        Trees.jungle(_canvas, x, y, z, 16 + tall + (hsh >> 18) % 3, hsh, _jungleTree);
      case biomeSnow:
        Trees.spruce(_canvas, x, y, z, 12 + tall, _spruceTree);
      case biomeMountain:
        if (y < 96) Trees.spruce(_canvas, x, y, z, 11 + tall, _spruceTree);
      case biomeDesert || biomeBeach:
        Trees.palm(_canvas, x, y, z, 8 + tall, hsh, _jungleTree);
    }
  }

  /// Grass, flowers, mushrooms, reeds, cacti and melons: one roll per column.
  void _plantSmall(ChunkWriter w, int x, int y, int z, int wx, int wz, int biome, int hsh) {
    final roll = hsh % 1000;
    switch (biome) {
      case biomeForest:
        if (roll < 185) {
          _setIfInside(w, x, y, z, _tallGrass);
        } else if (roll < 210) {
          _setIfInside(w, x, y, z, _mushroom);
        } else if (roll < 230) {
          _setIfInside(w, x, y, z, _flowerRed);
        }
      case biomePlains:
        if (roll < 144) {
          _setIfInside(w, x, y, z, _tallGrass);
        } else if (roll < 166) {
          _setIfInside(w, x, y, z, _flowerYellow);
        } else if (roll < 184) {
          _setIfInside(w, x, y, z, _flowerRed);
        }
      case biomeSwamp:
        // Godot tests PoolEdge first; the roll goes first here (same result,
        // four fewer height samples on most columns).
        if (roll < 550 && _poolEdge(wx, wz)) {
          _setIfInside(w, x, y, z, _reeds);
        } else if (roll < 278) {
          _setIfInside(w, x, y, z, _tallGrass);
        } else if (roll < 318) {
          _setIfInside(w, x, y, z, _mushroom);
        }
      case biomeJungle:
        if (roll < 292) {
          _setIfInside(w, x, y, z, _fern);
        } else if (roll < 382) {
          _setIfInside(w, x, y, z, _tallGrass);
        } else if (roll < 394) {
          _placeMelons(w, x, y, z, hsh);
        }
      case biomeDesert:
        if (roll < 12) {
          final ch = 2 + ((hsh >> 10) % 2);
          for (var i = 0; i < ch; i++) {
            _setIfInside(w, x, y + i, z, _cactus);
          }
        } else if (roll < 40) {
          _setIfInside(w, x, y, z, _deadBush);
        }
    }
  }

  /// A swamp column beside a pool (any of the four neighbours is one).
  bool _poolEdge(int wx, int wz) {
    for (var i = 0; i < 4; i++) {
      final nx = wx + (i == 0 ? 1 : (i == 1 ? -1 : 0));
      final nz = wz + (i == 2 ? 1 : (i == 3 ? -1 : 0));
      final nh = surfaceHeight(nx, nz);
      if (_swampPool(nx, nz, nh, _biomeFor(nx, nz, nh))) return true;
    }
    return false;
  }

  /// A melon patch: the block itself and up to two neighbours on the ground.
  void _placeMelons(ChunkWriter w, int x, int y, int z, int hsh) {
    _setIfInside(w, x, y, z, _melon);
    if ((hsh >> 14) % 2 == 0) _setIfInside(w, x + 1, y, z, _melon);
    if ((hsh >> 15) % 2 == 0) _setIfInside(w, x, y, z + 1, _melon);
  }

  /// Chunk-local: over air, or over leaves (trunks overwrite canopy).
  void _setIfInside(ChunkWriter w, int x, int y, int z, int id) => w.place(x, y, z, id, over: _isSoft);

  // --- structures ---------------------------------------------------------------
  // One candidate per 6x6-chunk region, decided by hash so every chunk agrees. A
  // chunk writes only the blocks of the structure that fall inside it.
  static const int _regionChunks = 6;

  static const _floorDiv = floorDiv;

  /// (x, y, z, type) of the structure whose region contains this chunk, or null.
  ({int x, int y, int z, int type})? _regionStructure(int regionX, int regionZ) {
    final h = hash(regionX * 7919, 11, regionZ * 104729);
    final sx = regionX * _regionChunks * sizeX + (h % (_regionChunks * sizeX - 24)) + 12;
    final sz = regionZ * _regionChunks * sizeZ + ((h >> 8) % (_regionChunks * sizeZ - 24)) + 12;
    final roll = (h >> 16) % 100;
    final surface = surfaceHeight(sx, sz);
    final biome = _biomeFor(sx, sz, surface);
    if (biome == biomeOcean) return null;
    if (roll < 45) {
      final sy = (surface - 14 - ((h >> 24) % 14)).clamp(14, surface - 10);
      return (x: sx, y: sy, z: sz, type: structDungeon);
    } else if (roll < 75) {
      return (x: sx, y: surface, z: sz, type: structTower);
    } else if (roll < 82) {
      return (x: sx, y: surface, z: sz, type: structCamp);
    } else if (biome == biomePlains || biome == biomeForest) {
      return (x: sx, y: surface, z: sz, type: structVillage);
    }
    return null;
  }

  /// Structures whose region touches the chunk: records of (x, y, z, type).
  List<({int x, int y, int z, int type})> structuresNear(int chunkX, int chunkZ) => structuresNearIn(chunkX, chunkZ, _dimension);

  List<({int x, int y, int z, int type})> structuresNearIn(int chunkX, int chunkZ, int dimension) {
    final list = <({int x, int y, int z, int type})>[];
    if (dimension == dimUnderworld) {
      final fx = _floorDiv(chunkX, _fortressRegionChunks), fz = _floorDiv(chunkZ, _fortressRegionChunks);
      for (var dz = -1; dz <= 1; dz++) {
        for (var dx = -1; dx <= 1; dx++) {
          final f = _fortressAt(fx + dx, fz + dz);
          if (f != null) list.add(f);
        }
      }
      return list;
    }
    final rx = _floorDiv(chunkX, _regionChunks), rz = _floorDiv(chunkZ, _regionChunks);
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        final s = _regionStructure(rx + dx, rz + dz);
        if (s != null && _structureAllowed(s)) list.add(s);
      }
    }
    final mx = _floorDiv(chunkX, _minorRegionChunks), mz = _floorDiv(chunkZ, _minorRegionChunks);
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        final s = _minorStructure(mx + dx, mz + dz);
        if (s != null && _structureAllowed(s)) list.add(s);
      }
    }
    return list;
  }

  void _buildStructures(ChunkWriter w) {
    final chunkX = w.chunkX, chunkZ = w.chunkZ;
    final rx = _floorDiv(chunkX, _regionChunks), rz = _floorDiv(chunkZ, _regionChunks);
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        final s = _regionStructure(rx + dx, rz + dz);
        if (s == null || !_structureAllowed(s)) continue;
        switch (s.type) {
          case structDungeon:
            _dungeon(w, s.x, s.y, s.z);
          case structTower:
            _tower(w, s.x, s.y, s.z);
          case structCamp:
            _camp(w, s.x, s.y, s.z);
          case structVillage:
            _village(w, s.x, s.y, s.z);
        }
      }
    }
    final mx = _floorDiv(chunkX, _minorRegionChunks), mz = _floorDiv(chunkZ, _minorRegionChunks);
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        final s = _minorStructure(mx + dx, mz + dz);
        if (s == null || !_structureAllowed(s)) continue;
        switch (s.type) {
          case structRuin:
            _ruins(w, s.x, s.y, s.z);
          case structWell:
            _well(w, s.x, s.y, s.z);
          case structMine:
            _mine(w, s.x, s.y, s.z);
          case structTemple:
            _temple(w, s.x, s.y, s.z);
        }
      }
    }
  }

  void _dungeon(ChunkWriter w, int cx, int cy, int cz) {
    // Three rooms in a row joined by corridors; boss room at the end with the chest.
    for (var room = 0; room < 3; room++) {
      final rcx = cx + room * 12, rcz = cz;
      final half = room == 2 ? 6 : 4;
      final hgt = room == 2 ? 6 : 4;
      for (var x = -half; x <= half; x++) {
        for (var z = -half; z <= half; z++) {
          for (var y = 0; y <= hgt; y++) {
            final wall = x == -half || x == half || z == -half || z == half || y == 0 || y == hgt;
            final id = wall ? (hash(rcx + x, cy + y, rcz + z) % 4 == 0 ? _mossyBricks : _stoneBricks) : _air;
            w.put(rcx + x, cy + y, rcz + z, id);
          }
        }
      }
      w.put(rcx - half + 1, cy + 1, rcz - half + 1, _lamp);
      w.put(rcx + half - 1, cy + 1, rcz + half - 1, _lamp);
      if (room < 2) w.put(rcx, cy + 1, rcz + 2, _spawnerId);
      if (room == 2) {
        w.put(rcx, cy + 1, rcz, _chest);
        w.put(rcx + 2, cy + 1, rcz - 2, _boneBlock);
        w.put(rcx - 3, cy + 1, rcz + 3, _goldOre);
      }
      if (room < 2) {
        for (var x = half; x <= half + 12 - 4; x++) {
          for (var y = 1; y <= 2; y++) {
            w.put(rcx + x, cy + y, rcz, _air);
          }
          w.put(rcx + x, cy, rcz, _stoneBricks);
          w.put(rcx + x, cy + 3, rcz, _stoneBricks);
          w.put(rcx + x, cy + 1, rcz - 1, _stoneBricks);
          w.put(rcx + x, cy + 2, rcz - 1, _stoneBricks);
          w.put(rcx + x, cy + 1, rcz + 1, _stoneBricks);
          w.put(rcx + x, cy + 2, rcz + 1, _stoneBricks);
        }
      }
    }
    // A shaft up to the surface from the first room, with ladders.
    final top = surfaceHeight(cx - 3, cz - 3);
    for (var y = cy + 1; y < top + 1; y++) {
      w.put(cx - 3, y, cz - 3, _air);
      w.put(cx - 3, y, cz - 4, y < top - 1 ? _stoneBricks : 0);
      w.put(cx - 3, y, cz - 3, _ladderId);
    }
  }

  void _tower(ChunkWriter w, int cx, int cy, int cz) {
    const h = 9;
    for (var x = -2; x <= 2; x++) {
      for (var z = -2; z <= 2; z++) {
        final wall = x.abs() == 2 || z.abs() == 2;
        for (var y = -3; y <= h; y++) {
          var id = _air;
          if (y < 0) {
            id = _stoneBricks;
          } else if (y == 0) {
            id = _stoneBricks;
          } else if (wall) {
            final door = z == 2 && x == 0 && y <= 2;
            final window = y % 3 == 2 && (x == 0 || z == 0);
            id = door || window ? _air : (hash(cx + x, cy + y, cz + z) % 5 == 0 ? _mossyBricks : _stoneBricks);
          } else if (y == h - 1) {
            id = _planks;
          }
          w.put(cx + x, cy + y, cz + z, id);
        }
        if (wall && (x + z) % 2 == 0) w.put(cx + x, cy + h + 1, cz + z, _stoneBricks);
      }
    }
    w.put(cx, cy + h, cz, _chest);
    w.put(cx - 1, cy + h, cz - 1, _lamp);
    for (var y = 1; y < h - 1; y++) {
      w.put(cx - 1, cy + y, cz - 1, _ladderId);
    }
    w.put(cx - 1, cy + h - 1, cz - 1, _air);
  }

  /// Stage 26: 4-7 huts on a ring around a central well, each levelled onto its
  /// own ground, joined to the well by gravel paths, plus a fenced wheat plot.
  /// `_hutCount` / `_hutAt` are the layout every chunk (and the probe) agrees on.
  static const int _villageRing = 11;

  int villageHutCount(int cx, int cz) => _hutCount(cx, cz);

  int _hutCount(int cx, int cz) => 4 + (hash(cx, 51, cz) % 4);

  /// Godot's `Mathf.RoundToInt` rounds half to even and Dart's `round` half away
  /// from zero; a cosine times the ring radius never lands on a half.
  ({int x, int z}) _hutAt(int cx, int cz, int i) {
    final n = _hutCount(cx, cz);
    final a = i * math.pi * 2 / n + (hash(cx, 52, cz) % 100) / 100.0;
    final r = _villageRing + (hash(cx, 53 + i, cz) % 3);
    return (x: cx + (math.cos(a) * r).round(), z: cz + (math.sin(a) * r).round());
  }

  /// World (x, z) of every hut centre, for the probe.
  List<({int x, int z})> villageHuts(int cx, int cz) => [for (var i = 0; i < _hutCount(cx, cz); i++) _hutAt(cx, cz, i)];

  static const int _villageClearRadius = 24;

  /// A forest village is a clearing and not huts under a canopy. Stage 42 does it
  /// by keeping the trees out ([_structureClearance]) instead of cutting them
  /// down: a saw that ran here after the trees left every crown it cut hanging
  /// over the village with no trunk under it.
  void _village(ChunkWriter w, int cx, int cy, int cz) {
    final n = _hutCount(cx, cz);
    final wy = surfaceHeight(cx, cz);
    for (var i = 0; i < n; i++) {
      final hut = _hutAt(cx, cz, i);
      final hy = surfaceHeight(hut.x, hut.z);
      _hut(w, hut.x, hy, hut.z, i);
      _path(w, hut.x, hut.z, cx, cz);
    }
    // Well
    for (var x = -1; x <= 1; x++) {
      for (var z = -1; z <= 1; z++) {
        final rim = x.abs() == 1 || z.abs() == 1;
        _levelColumn(w, cx + x, cz + z, wy - 1, wy + 5, _cobblestone);
        w.put(cx + x, wy, cz + z, rim ? _stoneBricks : _water);
        w.put(cx + x, wy - 1, cz + z, rim ? _stoneBricks : _water);
        for (var y = 1; y < 4; y++) {
          if (x.abs() == 1 && z.abs() == 1) w.put(cx + x, wy + y, cz + z, _oakLog);
        }
        w.put(cx + x, wy + 4, cz + z, _planks);
      }
    }
    w.put(cx + 3, wy, cz, _lamp);
    w.put(cx - 3, wy, cz, _lamp);
    // Farm plot: 9x7 fenced, two rows of ripe wheat on farmland either side of a
    // water channel.
    final fx = cx + 5, fz = cz - _villageRing - 6;
    final fy = surfaceHeight(fx, fz);
    for (var z = -3; z <= 3; z++) {
      for (var x = -4; x <= 4; x++) {
        final wx = fx + x, wz = fz + z;
        final edge = x.abs() == 4 || z.abs() == 3;
        _levelColumn(w, wx, wz, fy - 1, fy + 3, _dirt);
        if (edge) {
          w.put(wx, fy - 1, wz, _grass);
          w.put(wx, fy, wz, _fence);
        } else if (z == 0) {
          w.put(wx, fy - 1, wz, _water);
        } else {
          w.put(wx, fy - 1, wz, _farmland);
          w.put(wx, fy, wz, _wheat);
        }
      }
    }
    w.put(fx, fy, fz + 3, _air); // the gate
    w.put(fx + 4, fy + 1, fz + 3, _torch);
  }

  /// A gravel path along x then along z, one block wide, laid on each column's
  /// own ground.
  void _path(ChunkWriter w, int fromX, int fromZ, int toX, int toZ) {
    final stepX = toX > fromX ? 1 : -1, stepZ = toZ > fromZ ? 1 : -1;
    for (var x = fromX; x != toX; x += stepX) {
      if ((x - toX).abs() <= 2 && (fromZ - toZ).abs() <= 2) break;
      final y = surfaceHeight(x, fromZ);
      w.put(x, y - 1, fromZ, _gravel);
      w.put(x, y, fromZ, _air);
    }
    for (var z = fromZ; z != toZ; z += stepZ) {
      if ((z - toZ).abs() <= 2) break;
      final y = surfaceHeight(toX, z);
      w.put(toX, y - 1, z, _gravel);
      w.put(toX, y, z, _air);
    }
  }

  /// A 5x5 hut: cobblestone floor, plank walls with log corners, a door gap
  /// facing the well side, a glass window, a plank ceiling ringed with slabs,
  /// and inside a torch, a bed and a chest (`LootTables.tables['village']`).
  void _hut(ChunkWriter out, int cx, int cy, int cz, int variant) {
    const w = 2, d = 2, h = 4;
    final doorZ = variant % 2 == 0 ? d : -d;
    for (var x = -w; x <= w; x++) {
      for (var z = -d; z <= d; z++) {
        _levelColumn(out, cx + x, cz + z, cy - 1, cy + h + 2, _cobblestone);
        for (var y = -2; y <= h + 1; y++) {
          var id = _air;
          final wall = x.abs() == w || z.abs() == d;
          final corner = x.abs() == w && z.abs() == d;
          if (y < 0) {
            id = _cobblestone; // foundation
          } else if (y == 0) {
            id = _cobblestone; // floor
          } else if (y == h) {
            id = _planks; // ceiling
          } else if (y == h + 1) {
            id = wall ? _slab : (x == 0 && z == 0 ? _slab : _air); // slab roof rim + cap
          } else if (corner) {
            id = _oakLog;
          } else if (wall) {
            final door = z == doorZ && x == 0 && y <= 2;
            final window = y == 2 && (x == 0 && z == -doorZ);
            id = door ? _air : (window ? _glassId : _planks);
          }
          out.put(cx + x, cy + y, cz + z, id);
        }
      }
    }
    final back = -doorZ + (doorZ > 0 ? 1 : -1);
    final front = doorZ - (doorZ > 0 ? 1 : -1);
    out.put(cx - w + 1, cy + 1, cz + back, _chest);
    out.put(cx + w - 1, cy + 1, cz + back, _bed);
    out.put(cx, cy + 3, cz, _torch);
    if (variant == 2) out.put(cx + w - 1, cy + 1, cz + front, _craftingTable);
    if (variant == 3) out.put(cx - w + 1, cy + 1, cz + front, _furnace);
  }

  void _camp(ChunkWriter w, int cx, int cy, int cz) {
    for (var x = -3; x <= 3; x++) {
      for (var z = -2; z <= 2; z++) {
        // Stage 42: a block taller than it was, because the roof now carries a
        // block under each step and the shelter would have lost its headroom.
        final roof = 4 - z.abs();
        w.put(cx + x, cy + roof, cz + z, _planks);
        // Stage 42: the slope of the roof climbs by faces. Each row used to sit
        // one block over and one across from the next, touching it by an edge
        // alone, so the ridge of the tent hung over a gap it never reached.
        if (roof > 1) w.put(cx + x, cy + roof - 1, cz + z, _planks);
        if (x.abs() == 3) {
          // And the corner post stands on its own ground: pitched on a slope,
          // the camp used to hold a post in the air.
          var foot = cy;
          if (z.abs() == 2) {
            final ground = surfaceHeight(cx + x, cz + z);
            foot = math.min(cy, ground);
            // Pitched at the lip of a swamp pool, the post reaches the bed under
            // it instead of resting on the water lying on the bed.
            if (_swampPool(cx + x, cz + z, ground, _biomeFor(cx + x, cz + z, ground))) foot = math.min(foot, ground - 1);
            while (foot > 1 && foot > ground - 10 && _carved(cx + x, foot - 1, cz + z, ground)) {
              foot--; // a cave mouth under the corner is no reason to hang a post over it
            }
          }
          for (var y = foot; y < cy + roof; y++) {
            w.put(cx + x, y, cz + z, z.abs() == 2 ? _oakLog : _air);
          }
        }
      }
    }
    w.put(cx, cy, cz, _chest);
    w.put(cx + 6, cy, cz, _lamp);
    for (var y = math.min(cy - 1, surfaceHeight(cx + 6, cz)); y <= cy - 1; y++) {
      w.put(cx + 6, y, cz, _stone); // the lamp's block reaches the ground too
    }
  }

  // --- minor structures: ruins, wells, abandoned mines, desert temples ------------
  // A second, denser grid (4x4 chunks) with its own hash; a candidate is dropped
  // when it sits inside the 48-block footprint of any primary structure, so the two
  // layers never overwrite each other. The mine corridor (up to 30 long, underground
  // at [mineFloorY]) is the only piece that reaches past its own region.
  static const int _minorRegionChunks = 4;
  static const int _minorMargin = 16;
  static const int _primaryClearance = 48;

  /// Floor y of every mine corridor: the chest, spawner and torches sit one above.
  static const int mineFloorY = 24;

  ({int x, int y, int z, int type})? _minorStructure(int regionX, int regionZ) {
    final h = hash(regionX * 6151, 23, regionZ * 12289);
    const span = _minorRegionChunks * sizeX;
    final sx = regionX * span + _minorMargin + (h % (span - 2 * _minorMargin));
    final sz = regionZ * span + _minorMargin + ((h >> 8) % (span - 2 * _minorMargin));
    final roll = (h >> 16) % 100;
    final surface = surfaceHeight(sx, sz);
    final biome = _biomeFor(sx, sz, surface);
    if (surface <= seaLevel + 1) return null; // ocean, beach, river bed
    var type = structNone;
    switch (biome) {
      case biomePlains:
        type = roll < 45 ? structRuin : (roll < 75 ? structWell : (roll < 82 ? structMine : structNone));
      case biomeForest:
        type = roll < 55 ? structRuin : (roll < 65 ? structMine : structNone);
      case biomeMountain:
        type = roll < 70 ? structMine : structNone;
      case biomeSnow:
        type = roll < 25 ? structMine : structNone;
      case biomeDesert:
        type = roll < 55 ? structTemple : structNone;
    }
    if (type == structNone) return null;
    final prx = _floorDiv(_floorDiv(sx, sizeX), _regionChunks);
    final prz = _floorDiv(_floorDiv(sz, sizeZ), _regionChunks);
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        final p = _regionStructure(prx + dx, prz + dz);
        if (p == null) continue;
        if ((p.x - sx).abs() < _primaryClearance && (p.z - sz).abs() < _primaryClearance) return null;
      }
    }
    return (x: sx, y: surface, z: sz, type: type);
  }

  bool _isRock(int id) =>
      id == _stone || id == _darkStone || id == _coalOre || id == _ironOre || id == _goldOre;

  /// Fills the column below [floorY] down to the local ground and clears the air
  /// above it up to [clearTo], so a structure sits on the ground on a slope instead
  /// of floating or sinking.
  void _levelColumn(ChunkWriter w, int wx, int wz, int floorY, int clearTo, int fill) =>
      w.levelColumn(wx, wz, surfaceHeight(wx, wz), floorY, clearTo, fill);

  /// Broken stone-brick walls 2-4 high with gaps around a cracked cobblestone floor;
  /// a chest half the time, one or two plants growing on the wall tops.
  void _ruins(ChunkWriter w, int cx, int cy, int cz) {
    const half = 3;
    final h = hash(cx, 31, cz);
    final plantA = h % 24, plantB = (h >> 5) % 24;
    var edgeIndex = 0;
    for (var z = -half; z <= half; z++) {
      for (var x = -half; x <= half; x++) {
        final wx = cx + x, wz = cz + z;
        _levelColumn(w, wx, wz, cy - 1, cy + 5, _cobblestone);
        final hole = hash(wx, 32, wz) % 4 == 0;
        w.put(wx, cy - 1, wz, hole ? _grass : _cobblestone);
        final edge = x.abs() == half || z.abs() == half;
        if (!edge) continue;
        final wh = hash(wx, 33, wz);
        final height = wh % 10 < 3 ? 0 : 2 + ((wh >> 4) % 3);
        for (var y = 0; y < height; y++) {
          w.put(wx, cy + y, wz, hash(wx, cy + y, wz) % 5 < 2 ? _mossyBricks : _stoneBricks);
        }
        if (height > 0 && (edgeIndex == plantA || edgeIndex == plantB)) {
          w.put(wx, cy + height, wz, (wh >> 12) % 2 == 0 ? _tallGrass : _flowerRed);
        }
        edgeIndex++;
      }
    }
    if ((h >> 10) % 2 == 0) w.put(cx, cy, cz, _chest);
  }

  /// A 3x3 cobblestone ring one block above the ground, water four deep in the
  /// middle, two fence posts and a plank roof at height 3.
  void _well(ChunkWriter w, int cx, int cy, int cz) {
    for (var z = -1; z <= 1; z++) {
      for (var x = -1; x <= 1; x++) {
        final wx = cx + x, wz = cz + z;
        final rim = x.abs() == 1 || z.abs() == 1;
        _levelColumn(w, wx, wz, cy - 5, cy + 2, _cobblestone);
        for (var y = cy - 4; y <= cy; y++) {
          w.put(wx, y, wz, rim ? _cobblestone : _water);
        }
        w.put(wx, cy + 3, wz, _planks);
      }
    }
    for (var y = 1; y <= 2; y++) {
      w.put(cx - 1, cy + y, cz, _fence);
      w.put(cx + 1, cy + y, cz, _fence);
    }
  }

  /// A ladder shaft from the surface down to [mineFloorY], then a 3x3 corridor 20-30
  /// long towards +x with log-and-plank support beams every 4 blocks, a torch pair on
  /// every second beam, ore veins exposed in the walls, a chest at the end and a
  /// spawner a third of the time.
  void _mine(ChunkWriter w, int cx, int cy, int cz) {
    final h = hash(cx, 41, cz);
    final len = 20 + (h % 11);
    const fy = mineFloorY;
    // Head frame on the surface: a 3x3 clearing with four fence posts and a roof.
    for (var z = -1; z <= 1; z++) {
      for (var x = -1; x <= 1; x++) {
        _levelColumn(w, cx + x, cz + z, cy - 1, cy + 3, _cobblestone);
        w.put(cx + x, cy - 1, cz + z, _cobblestone);
        w.put(cx + x, cy + 2, cz + z, _planks);
        if (x.abs() == 1 && z.abs() == 1) {
          w.put(cx + x, cy, cz + z, _fence);
          w.put(cx + x, cy + 1, cz + z, _fence);
        }
      }
    }
    // Shaft: ladder from the corridor floor up through the surface block.
    for (var y = fy + 1; y <= cy; y++) {
      w.put(cx, y, cz, _ladderId);
    }
    for (var x = 1; x <= len; x++) {
      final wx = cx + x;
      for (var z = -2; z <= 2; z++) {
        for (var y = 0; y <= 4; y++) {
          final wy = fy + y, wz = cz + z;
          final inside = z.abs() <= 1 && y >= 1 && y <= 3;
          if (inside) {
            w.put(wx, wy, wz, _air);
            continue;
          }
          final cur = w.get(wx, wy, wz);
          if (cur == null) continue;
          if (cur == _air || cur == _lava || cur == _water) {
            w.put(wx, wy, wz, _stone);
            continue;
          }
          if (!_isRock(cur)) continue;
          final vein = hash(wx, wy, wz) % 100;
          if (vein < 5) {
            w.put(wx, wy, wz, _goldOre);
          } else if (vein < 18) {
            w.put(wx, wy, wz, _ironOre);
          }
        }
      }
      if (x % 4 == 2) {
        final lit = x % 8 == 2;
        for (var y = 1; y <= 2; y++) {
          w.put(wx, fy + y, cz - 1, _oakLog);
          w.put(wx, fy + y, cz + 1, _oakLog);
        }
        w.put(wx, fy + 3, cz, _planks);
        w.put(wx, fy + 3, cz - 1, lit ? _torch : _planks);
        w.put(wx, fy + 3, cz + 1, lit ? _torch : _planks);
      }
    }
    // Stage 28: a rail down the centre line, from the shaft to the chest.
    for (var x = 1; x < len; x++) {
      w.put(cx + x, fy + 1, cz, _railEw);
    }
    w.put(cx + len, fy + 1, cz, _chest);
    if ((h >> 8) % 3 == 0) w.put(cx + len - 3, fy + 1, cz, _spawnerId);
  }

  /// A sandstone step pyramid, 9x9 at the base and five levels of two blocks each,
  /// with a hollow 3x3x3 chamber at the base holding two chests and a lamp, a pressure
  /// plate in the chamber floor centre with TNT under it, and an entrance corridor on
  /// the south (+z) side.
  void _temple(ChunkWriter w, int cx, int cy, int cz) {
    for (var z = -4; z <= 4; z++) {
      for (var x = -4; x <= 4; x++) {
        _levelColumn(w, cx + x, cz + z, cy - 1, cy + 12, _sandstone);
      }
    }
    for (var level = 0; level < 5; level++) {
      final hw = 4 - level;
      for (var dy = 0; dy < 2; dy++) {
        for (var z = -hw; z <= hw; z++) {
          for (var x = -hw; x <= hw; x++) {
            w.put(cx + x, cy + level * 2 + dy, cz + z, _sandstone);
          }
        }
      }
    }
    for (var z = -1; z <= 1; z++) {
      for (var x = -1; x <= 1; x++) {
        for (var y = 1; y <= 3; y++) {
          w.put(cx + x, cy + y, cz + z, _air);
        }
      }
    }
    w.put(cx, cy - 1, cz, _tnt);
    w.put(cx, cy, cz, _pressurePlate); // stage 23: the trap that lights it
    w.put(cx - 1, cy + 1, cz - 1, _chest);
    w.put(cx + 1, cy + 1, cz - 1, _chest);
    w.put(cx, cy + 4, cz, _lamp);
    for (var z = 2; z <= 4; z++) {
      for (var y = 1; y <= 2; y++) {
        w.put(cx, cy + y, cz + z, _air);
      }
    }
  }

  // --- stage 29: the underworld -------------------------------------------------
  // A cavernous slab between the bedrock floor (y 7) and roof (y 100): 3D noise
  // opens about 40% of the volume, the rock is hellstone, a lava ocean fills
  // every open cell at y <= 28, soul sand patches the floors, glowstone hangs
  // from the ceilings, quartz veins the walls.
  static const int hellFloorY = 7, hellRoofY = 100, lavaSeaY = 28;

  bool _hellOpen(int wx, int y, int wz) {
    final n = _hell.getNoise3(wx.toDouble(), y * 1.4, wz.toDouble());
    // Solid bias near the floor and the roof so the slab has a floor to walk and a lid.
    var edge = 0.0;
    if (y < hellFloorY + 6) edge = (hellFloorY + 6 - y) / 6.0;
    if (y > hellRoofY - 8) edge = math.max(edge, (y - (hellRoofY - 8)) / 8.0);
    return n - edge * 0.6 > 0.08;
  }

  Uint8List _generateUnderworld(int chunkX, int chunkZ) {
    final blocks = Uint8List(volume);
    final ox = chunkX * sizeX, oz = chunkZ * sizeZ;
    final open = List<bool>.filled(sizeY, false);
    for (var z = 0; z < sizeZ; z++) {
      for (var x = 0; x < sizeX; x++) {
        final wx = ox + x, wz = oz + z;
        for (var y = 0; y < sizeY; y++) {
          open[y] = y > hellFloorY && y < hellRoofY && _hellOpen(wx, y, wz);
        }
        final patch = _hellPatch.getNoise2(wx.toDouble(), wz.toDouble()) > 0.38;
        for (var y = 0; y <= hellRoofY; y++) {
          int id;
          if (y == 0 || y == hellFloorY || y == hellRoofY) {
            id = _bedrock;
          } else if (open[y]) {
            id = y <= lavaSeaY ? _lava : _air;
          } else {
            id = _hellstone;
            final floorTop = y + 1 < sizeY && open[y + 1] && y > lavaSeaY;
            final ceiling = y > 0 && open[y - 1] && y > lavaSeaY + 2;
            if (floorTop && patch) {
              id = _soulSand;
            } else if (ceiling && hash(wx >> 1, y, wz >> 1) % 23 == 0) {
              id = _glowstone;
              // A cluster hangs one or two cells into the cavern below.
              final len = 1 + hash(wx, y, wz) % 2;
              for (var k = 1; k <= len; k++) {
                if (y - k > lavaSeaY && open[y - k]) blocks[index(x, y - k, z)] = _glowstone;
              }
            } else {
              final cell = hash(wx >> 1, y >> 1, wz >> 1);
              if (hash(wx, y, wz) % 100 < 55 && cell % 10000 < 650) id = _quartzOre;
            }
          }
          final i = index(x, y, z);
          if (blocks[i] == _air) blocks[i] = id; // a glowstone cluster written from above stays
        }
      }
    }
    _buildFortresses(ChunkWriter(blocks, chunkX, chunkZ));
    return blocks;
  }

  /// The fortress: one candidate per 8x8-chunk region (60% of regions), a
  /// nether-brick hall running +x from its origin. [_fortressAt] is what every
  /// chunk and the game agree on.
  static const int _fortressRegionChunks = 8;
  static const int structFortress = 9;

  ({int x, int y, int z, int type})? _fortressAt(int regionX, int regionZ) {
    final h = hash(regionX * 7127, 29, regionZ * 15919);
    const span = _fortressRegionChunks * sizeX;
    final sx = regionX * span + 16 + h % (span - 96);
    final sz = regionZ * span + 16 + (h >> 8) % (span - 32);
    final sy = 60 - 10 + (h >> 20) % 21;
    if ((h >> 16) % 10 >= 6) return null;
    return (x: sx, y: sy, z: sz, type: structFortress);
  }

  int _fortressLength(int sx, int sz) => 40 + hash(sx, 30, sz) % 21;

  /// The layout the probe and `Game` read: the hall's length and far end, the
  /// throne room centre, the core block cell, the blaze spot (hall middle) and
  /// the two side-room chests.
  ({int length, IVec3 hallEnd, IVec3 throne, IVec3 core, IVec3 blaze, IVec3 chestA, IVec3 chestB}) fortressLayout(
      int sx, int sy, int sz) {
    final len = _fortressLength(sx, sz);
    return (
      length: len,
      hallEnd: IVec3(sx + len, sy, sz),
      throne: IVec3(sx + len + 5, sy, sz),
      core: IVec3(sx + len + 5, sy, sz),
      blaze: IVec3(sx + len ~/ 2, sy + 1, sz),
      chestA: IVec3(sx + len ~/ 3, sy + 1, sz + 7),
      chestB: IVec3(sx + len * 2 ~/ 3, sy + 1, sz - 7),
    );
  }

  void _buildFortresses(ChunkWriter w) {
    final fx = _floorDiv(w.chunkX, _fortressRegionChunks), fz = _floorDiv(w.chunkZ, _fortressRegionChunks);
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        final f = _fortressAt(fx + dx, fz + dz);
        if (f != null) _fortress(w, f.x, f.y, f.z);
      }
    }
  }

  /// A hall 5 wide x 5 tall (interior) and 40-60 long of nether brick, pillars
  /// every 8 blocks down to the bedrock floor, arched windows on both sides,
  /// glowstone in the ceiling every 8 blocks, two side rooms (one chest each)
  /// off the hall, a blaze spot at the middle, and a throne room 9x9x7 at the
  /// far end with lava channels along its walls and the fortress core in the
  /// centre of its floor.
  void _fortress(ChunkWriter w, int sx, int sy, int sz) {
    final len = _fortressLength(sx, sz);
    // Hall shell: walls z = +-3, floor y = sy, ceiling y = sy + 6, interior air.
    for (var x = 0; x <= len; x++) {
      final wx = sx + x;
      if (wx < w.ox - 1 || wx > w.ox + sizeX) continue;
      for (var z = -3; z <= 3; z++) {
        for (var y = 0; y <= 6; y++) {
          final wall = z.abs() == 3 || y == 0 || y == 6;
          var id = wall ? _netherBrick : _air;
          if (wall && z.abs() == 3 && y >= 2 && y <= 4 && x % 6 == 3 && x > 2 && x < len - 2) id = _air; // window
          if (wall && z.abs() == 3 && y == 3 && x % 6 == 0) id = _glowstone; // a sconce between the windows
          if (y == 6 && z == 0 && x % 8 == 4) id = _glowstone;
          w.put(wx, sy + y, sz + z, id);
        }
      }
      // Pillars to the bedrock floor at both wall lines, every 8 blocks.
      if (x % 8 == 0) {
        for (var y = sy - 1; y > hellFloorY; y--) {
          w.put(wx, y, sz - 3, _netherBrick);
          w.put(wx, y, sz + 3, _netherBrick);
        }
      }
    }
    // Side rooms: 5x5 interior off the +z wall at a third, off the -z wall at two thirds.
    _sideRoom(w, sx + len ~/ 3, sy, sz, 1);
    _sideRoom(w, sx + len * 2 ~/ 3, sy, sz, -1);
    // Throne room: 9x9 interior, 7 tall, centred 5 past the hall's end.
    final cx = sx + len + 5, cz = sz;
    for (var x = -5; x <= 5; x++) {
      for (var z = -5; z <= 5; z++) {
        final wx = cx + x, wz = cz + z;
        if (wx < w.ox || wx >= w.ox + sizeX || wz < w.oz || wz >= w.oz + sizeZ) continue;
        for (var y = 0; y <= 8; y++) {
          final wall = x.abs() == 5 || z.abs() == 5 || y == 0 || y == 8;
          var id = wall ? _netherBrick : _air;
          if (x == -5 && z.abs() <= 1 && y >= 1 && y <= 4) id = _air; // the door from the hall
          if (wall && y == 4 && x.abs() != 5 && z.abs() == 5 && x % 3 == 0) id = _glowstone; // sconces along both side walls
          if (wall && y == 4 && x == 5 && z % 3 == 0) id = _glowstone; // and the back wall
          if (y == 0 && (z.abs() == 4 || x.abs() == 4) && !(x == -4 && z.abs() <= 1)) id = _lava; // moat sunk in the floor ring
          if (y == 8 && (x % 3 == 0) && (z % 3 == 0)) id = _glowstone;
          if (y == 0 && x == 0 && z == 0) id = _fortressCore;
          w.put(wx, sy + y, wz, id);
        }
        // The room floor's underside and pillars so the moat has a bed.
        w.put(wx, sy - 1, wz, _netherBrick);
        if (x.abs() == 5 && z.abs() == 5) {
          for (var y = sy - 2; y > hellFloorY; y--) {
            w.put(wx, y, wz, _netherBrick);
          }
        }
      }
    }
    // A glowstone-lit dais step at the far wall behind the core.
    for (var z = -2; z <= 2; z++) {
      w.put(cx + 3, sy + 1, cz + z, _netherBrick);
    }
    w.put(cx + 3, sy + 2, cz, _glowstone);
  }

  void _sideRoom(ChunkWriter w, int rx, int ry, int hz, int side) {
    // Interior z from hz + side*4 .. hz + side*8 (5 cells), x rx-2..rx+2; the hall wall opens.
    final zc = hz + side * 6;
    for (var x = -3; x <= 3; x++) {
      for (var z = -3; z <= 3; z++) {
        final wx = rx + x, wz = zc + z;
        if (wx < w.ox || wx >= w.ox + sizeX || wz < w.oz || wz >= w.oz + sizeZ) continue;
        for (var y = 0; y <= 5; y++) {
          final wall = x.abs() == 3 || z.abs() == 3 || y == 0 || y == 5;
          var id = wall ? _netherBrick : _air;
          if (wz == hz + side * 3 && x.abs() <= 1 && y >= 1 && y <= 3) id = _air; // doorway through the hall wall
          w.put(wx, ry + y, wz, id);
        }
      }
    }
    w.put(rx, ry + 1, hz + side * 7, _chest);
    w.put(rx, ry + 4, zc, _glowstone);
  }
}
