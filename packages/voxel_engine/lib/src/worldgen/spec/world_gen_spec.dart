import 'package:voxel_engine/core.dart';

import 'spec_generator.dart';
import 'structure.dart';

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
///   strata: [Stratum('deepslate', belowY: 22)],
///   ores: [Ore('coal_ore', share: 0.11)],
///   structures: [StructureSpec('well', Well(rim: 'cobblestone', water: 'water', posts: 'fence', roof: 'planks'))],
/// );
/// ```
///
/// A world with a [cavern] has a roof: the underworld a portal leads to.
///
/// A spec is plain data plus pure callbacks, so it crosses to the worker
/// isolates: build the generator factory as `() => spec.compile(ids, seed)`
/// in a static or top-level function, never in a method that could capture
/// `this`.
class WorldGenSpec {
  /// A world. [biomes] are tried in order and the first whose [Climate]
  /// matches a column wins; the last one is the fallback, whatever its
  /// climate. [ocean] and [beach] take the columns below and just above
  /// [seaLevel] when given. With a [cavern] the world is a roofed slab of
  /// [stone] instead (see [CavernSpec]).
  const WorldGenSpec({
    required this.biomes,
    this.seaLevel = 46,
    this.terrain = const TerrainRecipe(),
    this.stone = 'stone',
    this.water = 'water',
    this.bedrock,
    this.ocean,
    this.beach,
    this.strata = const [],
    this.ores = const [],
    this.caves = const CaveSpec(),
    this.structures = const [],
    this.cavern,
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

  /// The rock by depth, tried in order: a cell of rock below a stratum's
  /// `belowY` is its block instead of [stone]. Ores vein it as they do stone.
  final List<Stratum> strata;

  /// Ores, tried in order.
  final List<Ore> ores;

  /// Caves.
  final CaveSpec caves;

  /// Structures, each on its own grid, tried in order: a site within reach of
  /// an earlier structure's is dropped, so two never overlap.
  final List<StructureSpec> structures;

  /// The roof and floor of a world that is one great cave, or null for open
  /// sky over [terrain].
  final CavernSpec? cavern;

  /// Every block name the spec uses, so a game can check its table has them.
  Set<String> get blockNames => {
    stone,
    water,
    ?bedrock,
    for (final b in [...biomes, ?ocean, ?beach]) ...b.blockNames,
    for (final s in strata) s.block,
    for (final o in ores) o.block,
    ?caves.lava,
    for (final s in structures) ...s.structure.blockNames,
    for (final h in cavern?.hangs ?? const <Plant>[]) h.block,
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

/// A world that is one great cave: a slab of the world's stone between a
/// floor and a roof of its bedrock, opened by 3D noise into caverns, the
/// world's sea (its `water`, lava in an underworld) filling every open cell up
/// to its `seaLevel`.
///
/// Its biomes cover the floors: each floor's top block is the column's
/// biome's `top` or the first of its `covers` that holds there (chosen by
/// climate, as on the surface), with that biome's plants on it; [hangs] hang
/// from the ceilings. A cavern grows no trees, holds no pools and carves no
/// caves, and its plants neither spread nor seek water: the spec throws when
/// its biomes say otherwise or its caves are on. Its ores and strata vein the
/// rock, and its structures stand on the lowest floor above the sea, which is
/// what `SpecGenerator.surfaceHeight` answers.
class CavernSpec {
  /// A cavern between [floor] and [roof]; noise over [threshold] is open (the
  /// default opens about two fifths of the slab), [scale] stretches the
  /// caverns sideways.
  const CavernSpec({this.floor = 7, this.roof = 100, this.threshold = 0.08, this.scale = 1.0, this.hangs = const []})
    : assert(floor > 0 && roof > floor + 16, 'a cavern needs room between its floor and its roof');

  /// The height of the bedrock floor.
  final int floor;

  /// The height of the bedrock roof.
  final int roof;

  /// Noise (-1..1) over this is open: higher closes the caverns.
  final double threshold;

  /// Horizontal stretch: 2 makes every cavern twice as wide.
  final double scale;

  /// What hangs from the ceilings above the sea, one roll per ceiling, tried
  /// in order: a [Plant]'s height is how far it hangs down.
  final List<Plant> hangs;
}

/// A window of climate a biome claims. Temperature and humidity are noise in
/// -1..1 (temperature drops with altitude); height is the surface height.
class Climate {
  /// Every bound left null is open.
  const Climate({
    this.minTemperature,
    this.maxTemperature,
    this.minHumidity,
    this.maxHumidity,
    this.minHeight,
    this.maxHeight,
  });

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

/// What falls from a biome's sky when the weather turns: Minecraft's own
/// three. A game reads it; the generator does not.
enum Precipitation {
  /// Rain, and in a storm, lightning.
  rain,

  /// Snow, whatever the storm.
  snow,

  /// Nothing: the sky stays clear (a desert).
  none,
}

/// One biome: what covers the ground, what grows on it, what falls on it.
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
    this.covers = const [],
    this.pools,
    this.ice,
    this.precipitation = Precipitation.rain,
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

  /// The trees it grows, one picked per tree by its roll, weighted by
  /// [TreeSpec.weight].
  final List<TreeSpec> trees;

  /// Per cent of tree patches that hold a tree.
  final int treeChance;

  /// Small plants, one roll per column, tried in order.
  final List<Plant> plants;

  /// What covers the ground instead of [top] where the surface stands in a
  /// cover's window and its roll hits, tried in order: snow on the peaks,
  /// gravel on the sea floor, patches of mud.
  final List<Cover> covers;

  /// Shallow pools in the low ground, or null for none.
  final Pools? pools;

  /// The block the sea's surface freezes to here, or null for open water.
  final String? ice;

  /// What falls here when the weather turns.
  final Precipitation precipitation;

  /// Every block this biome places.
  Set<String> get blockNames => {
    top,
    under,
    for (final t in trees) ...t.blockNames,
    for (final p in plants) p.block,
    for (final c in covers) c.block,
    ?pools?.bed,
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
  /// tall; [vines] hang from a jungle tree's crowns. [weight] is its share of
  /// its biome's trees; it grows only on ground below [belowY].
  const TreeSpec(
    this.shape, {
    required this.log,
    required this.leaves,
    this.vines,
    this.minHeight = 9,
    this.maxHeight = 12,
    this.weight = 1,
    this.belowY,
  }) : assert(minHeight <= maxHeight),
       assert(weight > 0);

  /// An oak, 9-12 tall.
  const TreeSpec.oak({
    required String log,
    required String leaves,
    int minHeight = 9,
    int maxHeight = 12,
    int weight = 1,
    int? belowY,
  }) : this(
         TreeShape.oak,
         log: log,
         leaves: leaves,
         minHeight: minHeight,
         maxHeight: maxHeight,
         weight: weight,
         belowY: belowY,
       );

  /// A spruce, 12-16 tall.
  const TreeSpec.spruce({
    required String log,
    required String leaves,
    int minHeight = 12,
    int maxHeight = 16,
    int weight = 1,
    int? belowY,
  }) : this(
         TreeShape.spruce,
         log: log,
         leaves: leaves,
         minHeight: minHeight,
         maxHeight: maxHeight,
         weight: weight,
         belowY: belowY,
       );

  /// A palm, 8-12 tall.
  const TreeSpec.palm({
    required String log,
    required String leaves,
    int minHeight = 8,
    int maxHeight = 12,
    int weight = 1,
    int? belowY,
  }) : this(
         TreeShape.palm,
         log: log,
         leaves: leaves,
         minHeight: minHeight,
         maxHeight: maxHeight,
         weight: weight,
         belowY: belowY,
       );

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

  /// Its share of its biome's trees: a tree of weight 3 beside one of weight 1
  /// grows three times as often.
  final int weight;

  /// It grows only where the ground (the first air cell) is below this, or
  /// anywhere when null: no spruce on the peaks.
  final int? belowY;

  /// Every block this tree places.
  Set<String> get blockNames => {log, leaves, ?vines};
}

/// A small plant on a biome's surface.
class Plant {
  /// [block] on [perMille] of the columns, [height] to [maxHeight] blocks
  /// tall (a cactus). [spread] is how many of the four neighbours may grow
  /// one too, each on a coin's roll (a patch of melons); [byWater] grows it
  /// only beside water at the surface (reeds), and a column away from water
  /// skips it without spending its share.
  const Plant(
    this.block, {
    required this.perMille,
    this.height = 1,
    int? maxHeight,
    this.spread = 0,
    this.byWater = false,
  }) : maxHeight = maxHeight ?? height,
       assert(height >= 1),
       assert(spread >= 0 && spread <= 4);

  /// The plant block.
  final String block;

  /// How many columns in a thousand grow it.
  final int perMille;

  /// How many blocks tall it stands, at the least.
  final int height;

  /// How many blocks tall it stands, at the most.
  final int maxHeight;

  /// How many of the four neighbours (+x, +z, -x, -z, in that order) may
  /// grow one too, where their ground is level with this one's.
  final int spread;

  /// Whether it grows only beside water: one of the four neighbours is the
  /// sea's, a river's or a pool's surface.
  final bool byWater;
}

/// The rock of a world below a height: dark stone in the deep.
class Stratum {
  /// [block] instead of the world's stone below [belowY].
  const Stratum(this.block, {required this.belowY});

  /// The rock block.
  final String block;

  /// Rock below this height is [block].
  final int belowY;
}

/// A biome's surface block where the ground stands in a window of height
/// and a roll hits: snow above a height, patches of mud.
class Cover {
  /// [block] on [perMille] of the columns whose surface height (the first air
  /// cell) is in [minHeight]..[maxHeight]; one roll per [patch] x [patch]
  /// square of columns, so a cover lies in patches.
  const Cover(this.block, {this.perMille = 1000, this.minHeight, this.maxHeight, this.patch = 1})
    : assert(perMille > 0 && perMille <= 1000),
      assert(patch >= 1);

  /// The surface block.
  final String block;

  /// How many columns (or patches) in a thousand it covers.
  final int perMille;

  /// The lowest surface height, or null.
  final int? minHeight;

  /// The highest surface height, or null.
  final int? maxHeight;

  /// The side of the square one roll covers, in blocks.
  final int patch;
}

/// Shallow pools: one block of the world's water over [bed], wherever noise
/// runs over [threshold] on land above the sea and the four neighbours stand
/// no lower, so the water stays where it is.
class Pools {
  /// Pools over [bed]; [threshold] in -1..1 (higher, fewer pools), [scale]
  /// stretches them sideways.
  const Pools({required this.bed, this.threshold = 0.28, this.scale = 1.0});

  /// What lies under the water.
  final String bed;

  /// Noise (-1..1) over this is a pool.
  final double threshold;

  /// Horizontal stretch: 2 makes every pool twice as wide.
  final double scale;
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
/// when null), its [structure] built around a site on the surface (or its
/// `depth` under it).
///
/// ```dart
/// StructureSpec('well', Well(rim: 'cobblestone', water: 'water', posts: 'fence', roof: 'planks'), chance: 0.4)
/// StructureSpec('hut', CustomStructure(hut, radius: 4))
/// ```
class StructureSpec {
  /// A structure: [name] is what [SpecGenerator.structuresNear] answers,
  /// [structure] what is drawn.
  const StructureSpec(this.name, this.structure, {this.regionChunks = 6, this.chance = 0.3, this.biomes})
    : assert(chance >= 0 && chance <= 1);

  /// The structure's name, what [SpecGenerator.structuresNear] answers.
  final String name;

  /// What is drawn, how far it reaches and what blocks it uses.
  final Structure structure;

  /// The side of a region, in chunks.
  final int regionChunks;

  /// The share of regions holding one.
  final double chance;

  /// The land biomes it stands on, or null for any land.
  final List<String>? biomes;
}
