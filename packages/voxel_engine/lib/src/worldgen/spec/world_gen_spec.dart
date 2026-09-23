import 'package:voxel_engine/core.dart';

import 'spec_generator.dart';
import 'structure_site.dart';

/// A whole world described as data: its terrain, biomes, ores, caves and
/// structures, with blocks named by string. [compile] turns it into a
/// [ChunkGenerator] against a game's block ids.
///
/// ```dart
/// const world = WorldGenSpec(
///   biomes: [
///     Biome('desert', top: 'sand', under: 'sand', climate: Climate.hotDry),
///     Biome('plains', top: 'grass', under: 'dirt',
///         trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')], treeChance: 20),
///   ],
///   ores: [Ore('coal_ore', share: 0.11)],
/// );
/// ```
///
/// A spec is plain data plus pure callbacks, so it crosses to the worker
/// isolates: build the generator factory as `() => spec.compile(ids, seed)`
/// in a static or top-level function, never in a method that could capture
/// `this`.
class WorldGenSpec {
  /// A world. [biomes] are tried in order and the first whose [Climate]
  /// matches a column wins; the last one is the fallback, whatever its
  /// climate. [ocean] and [beach] take the columns below and just above
  /// [seaLevel] when given.
  const WorldGenSpec({
    required this.biomes,
    this.seaLevel = 46,
    this.terrain = const TerrainRecipe(),
    this.stone = 'stone',
    this.water = 'water',
    this.bedrock,
    this.ocean,
    this.beach,
    this.ores = const [],
    this.caves = const CaveSpec(),
    this.structures = const [],
  });

  /// Land biomes, tried in order; at least one.
  final List<Biome> biomes;

  /// Water fills every open cell up to this height.
  final int seaLevel;

  /// How high the ground stands.
  final TerrainRecipe terrain;

  /// The rock under every biome's soil.
  final String stone;

  /// What fills the sea.
  final String water;

  /// The block at y 0, or null for [stone].
  final String? bedrock;

  /// The biome under the sea (more than two blocks below [seaLevel]).
  final Biome? ocean;

  /// The biome of the shore (at most one block above [seaLevel]).
  final Biome? beach;

  /// Ores, tried in order.
  final List<Ore> ores;

  /// Caves.
  final CaveSpec caves;

  /// Structures, each on its own grid.
  final List<StructureSpec> structures;

  /// Every block name the spec uses, so a game can check its table has them.
  Set<String> get blockNames => {
        stone,
        water,
        ?bedrock,
        for (final b in [...biomes, ?ocean, ?beach]) ...b.blockNames,
        for (final o in ores) o.block,
        ?caves.lava,
      };

  /// The generator of this world for [seed], resolving block names through
  /// [ids]. Throws [ArgumentError] naming the first block [ids] lacks.
  SpecGenerator compile(Map<String, int> ids, int seed) => SpecGenerator(this, ids, seed);
}

/// How high the ground stands: a continental land mask between [lowland] and
/// [highland], rolling hills, ridged mountains inland and rivers carved to
/// just under the sea.
class TerrainRecipe {
  /// The continental recipe; every size is in blocks.
  const TerrainRecipe({
    this.lowland = 24,
    this.highland = 54,
    this.hills = 11,
    this.coastHills = 4,
    this.mountainBase = 18,
    this.mountainRidge = 48,
    this.rivers = true,
    this.scale = 1.0,
  }) : flatHeight = null;

  /// Level ground at [height] everywhere: a builder's world, a test's floor.
  const TerrainRecipe.flat(int height)
      : flatHeight = height,
        lowland = 0,
        highland = 0,
        hills = 0,
        coastHills = 0,
        mountainBase = 0,
        mountainRidge = 0,
        rivers = false,
        scale = 1.0;

  /// The height of a flat world, or null for the continental recipe.
  final int? flatHeight;

  /// The ground of the deepest ocean floor.
  final double lowland;

  /// The ground of the plains, far inland.
  final double highland;

  /// How far hills rise and fall inland.
  final double hills;

  /// How far hills rise and fall at the coast.
  final double coastHills;

  /// How high a mountain range lifts the ground at its foot.
  final double mountainBase;

  /// How much more a ridge adds on top.
  final double mountainRidge;

  /// Whether rivers are carved.
  final bool rivers;

  /// Horizontal stretch: 2 makes continents, hills and rivers twice as wide.
  final double scale;
}

/// A window of climate a biome claims. Temperature and humidity are noise in
/// -1..1 (temperature drops with altitude); height is the surface height.
class Climate {
  /// Every bound left null is open.
  const Climate({this.minTemperature, this.maxTemperature, this.minHumidity, this.maxHumidity, this.minHeight, this.maxHeight});

  /// Anywhere.
  static const Climate any = Climate();

  /// Frozen ground.
  static const Climate cold = Climate(maxTemperature: -0.35);

  /// Hot and dry: a desert.
  static const Climate hotDry = Climate(minTemperature: 0.30, maxHumidity: 0.05);

  /// Hot and wet: a jungle.
  static const Climate hotWet = Climate(minTemperature: 0.22, minHumidity: 0.28);

  /// Wet: a forest.
  static const Climate wet = Climate(minHumidity: 0.22);

  /// High ground.
  static const Climate highlands = Climate(minHeight: 86);

  /// The lowest temperature, or null.
  final double? minTemperature;

  /// The highest temperature, or null.
  final double? maxTemperature;

  /// The lowest humidity, or null.
  final double? minHumidity;

  /// The highest humidity, or null.
  final double? maxHumidity;

  /// The lowest surface height, or null.
  final int? minHeight;

  /// The highest surface height, or null.
  final int? maxHeight;

  /// Whether a column of [temperature], [humidity] and surface [height] lies
  /// in this window.
  bool contains(double temperature, double humidity, int height) =>
      (minTemperature == null || temperature >= minTemperature!) &&
      (maxTemperature == null || temperature <= maxTemperature!) &&
      (minHumidity == null || humidity >= minHumidity!) &&
      (maxHumidity == null || humidity <= maxHumidity!) &&
      (minHeight == null || height >= minHeight!) &&
      (maxHeight == null || height <= maxHeight!);
}

/// One biome: what covers the ground, what grows on it.
class Biome {
  /// A biome named [name] with [top] on its surface over [under] soil
  /// [underDepth] deep. [treeChance] is the per cent of tree patches (7 x 7
  /// blocks, one tree at most) that grow one of [trees].
  const Biome(
    this.name, {
    required this.top,
    String? under,
    this.underDepth = 3,
    this.climate = Climate.any,
    this.trees = const [],
    this.treeChance = 0,
    this.plants = const [],
    this.ice,
  }) : under = under ?? top;

  /// The biome's name, what [SpecGenerator.biomeAt] answers.
  final String name;

  /// The surface block.
  final String top;

  /// The soil under [top].
  final String under;

  /// How deep the soil runs under the surface block.
  final int underDepth;

  /// Where this biome grows.
  final Climate climate;

  /// The trees it grows, one picked per tree by its roll.
  final List<TreeSpec> trees;

  /// Per cent of tree patches that hold a tree.
  final int treeChance;

  /// Small plants, one roll per column, tried in order.
  final List<Plant> plants;

  /// The block the sea's surface freezes to here, or null for open water.
  final String? ice;

  /// Every block this biome places.
  Set<String> get blockNames => {
        top,
        under,
        for (final t in trees) ...t.blockNames,
        for (final p in plants) p.block,
        ?ice,
      };
}

/// The tree shapes of `Trees`.
enum TreeShape {
  /// A trunk, two limbs and a round crown.
  oak,

  /// A 2 x 2 trunk under a crown five wide.
  bigOak,

  /// Tiers of leaves on a tall trunk.
  spruce,

  /// A flat drooping canopy.
  willow,

  /// A 2 x 2 giant with two crowns and vines.
  jungle,

  /// A leaning trunk under a star of fronds.
  palm,
}

/// A tree a biome grows.
class TreeSpec {
  /// A [shape] of [log] and [leaves], its trunk [minHeight] to [maxHeight]
  /// tall; [vines] hang from a jungle tree's crowns.
  const TreeSpec(this.shape, {required this.log, required this.leaves, this.vines, this.minHeight = 9, this.maxHeight = 12})
      : assert(minHeight <= maxHeight);

  /// An oak, 9-12 tall.
  const TreeSpec.oak({required String log, required String leaves, int minHeight = 9, int maxHeight = 12})
      : this(TreeShape.oak, log: log, leaves: leaves, minHeight: minHeight, maxHeight: maxHeight);

  /// A spruce, 12-16 tall.
  const TreeSpec.spruce({required String log, required String leaves, int minHeight = 12, int maxHeight = 16})
      : this(TreeShape.spruce, log: log, leaves: leaves, minHeight: minHeight, maxHeight: maxHeight);

  /// A palm, 8-12 tall.
  const TreeSpec.palm({required String log, required String leaves, int minHeight = 8, int maxHeight = 12})
      : this(TreeShape.palm, log: log, leaves: leaves, minHeight: minHeight, maxHeight: maxHeight);

  /// The shape.
  final TreeShape shape;

  /// The trunk block.
  final String log;

  /// The crown block.
  final String leaves;

  /// The vine block, or null.
  final String? vines;

  /// The shortest trunk.
  final int minHeight;

  /// The tallest trunk.
  final int maxHeight;

  /// Every block this tree places.
  Set<String> get blockNames => {log, leaves, ?vines};
}

/// A small plant on a biome's surface.
class Plant {
  /// [block] on [perMille] of the columns, [height] blocks tall (a cactus).
  const Plant(this.block, {required this.perMille, this.height = 1});

  /// The plant block.
  final String block;

  /// How many columns in a thousand grow it.
  final int perMille;

  /// How many blocks tall it stands.
  final int height;
}

/// An ore of a world.
class Ore {
  /// [block] in [share] of the rock's vein cells (0..1) below [belowY].
  const Ore(this.block, {required this.share, this.belowY = 1 << 30});

  /// The ore block.
  final String block;

  /// Its share of the vein cells, 0..1.
  final double share;

  /// It appears only below this height.
  final int belowY;
}

/// The caves of a world.
class CaveSpec {
  /// Caves on, with [lava] filling what opens at or below [lavaBelowY].
  const CaveSpec({this.enabled = true, this.lava, this.lavaBelowY = 10});

  /// No caves.
  static const CaveSpec none = CaveSpec(enabled: false);

  /// Whether caves are carved.
  final bool enabled;

  /// The deep block, or null for air all the way down.
  final String? lava;

  /// Lava fills carved cells at or below this height.
  final int lavaBelowY;
}

/// A structure of a world: at most one per region of [regionChunks] square,
/// in [chance] of the regions, on the land biomes named in [biomes] (any land
/// when null), built by [build] around a site on the surface.
class StructureSpec {
  /// A structure. [radius] is how far it reaches from its site, in blocks:
  /// trees stay clear of it, and the site stays that far inside its region.
  const StructureSpec(
    this.name, {
    required this.build,
    this.regionChunks = 6,
    this.chance = 0.3,
    this.biomes,
    this.radius = 8,
    this.depth = 0,
  }) : assert(chance >= 0 && chance <= 1);

  /// The structure's name, what [SpecGenerator.structuresNear] answers.
  final String name;

  /// Draws the structure; called once per chunk it may reach, and must draw
  /// the same thing every time (roll with [StructureSite.roll]).
  final StructureBuild build;

  /// The side of a region, in chunks.
  final int regionChunks;

  /// The share of regions holding one.
  final double chance;

  /// The land biomes it stands on, or null for any land.
  final List<String>? biomes;

  /// How far it reaches from its site, in blocks.
  final int radius;

  /// How far under the surface its site sits (a dungeon), 0 on the surface.
  final int depth;
}
