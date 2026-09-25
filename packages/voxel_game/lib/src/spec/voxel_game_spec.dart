import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/worldgen.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../mobs/mob.dart';
import '../mobs/mob_spec.dart';
import '../player/player_spec.dart';
import '../world/game_world.dart';
import 'signal_spec.dart';
import 'sky_spec.dart';
import 'sound_spec.dart';

/// A whole game, declared: its blocks, items and recipes, how its world is
/// generated, its player, its mobs and its sky. [VoxelGameWidget] (or
/// `runVoxelGame`) turns it into a playable world.
///
/// ```dart
/// runVoxelGame(VoxelGameSpec(
///   blocks: [
///     BlockType('stone', color: 0x7F7F84, hardness: 1.5, tool: 'pickaxe'),
///     BlockType('grass', color: 0x4C9437, drop: 'dirt'),
///     BlockType('dirt', color: 0x74502F),
///   ],
///   world: WorldGenSpec(biomes: [Biome('plains', top: 'grass', under: 'dirt')]),
/// ));
/// ```
class VoxelGameSpec {
  /// A game. [blocks] need not start with air: it is added.
  const VoxelGameSpec({
    required this.blocks,
    required this.world,
    this.items = const [],
    this.recipes = const [],
    this.player = const PlayerSpec(),
    this.mobs = const [],
    this.sky = const SkySpec(),
    this.sounds = const SoundSpec(),
    this.signals,
    this.seed = 1,
    this.renderDistance = 6,
    this.mining = const MiningRules(),
    this.liquids = const {},
    this.systems = const [],
    this.onBlockBroken,
    this.onBlockPlaced,
    this.onMobKilled,
    this.onTick,
  });

  /// The blocks, air first or added; their order is the save contract.
  final List<BlockType> blocks;

  /// How the world is generated.
  final WorldGenSpec world;

  /// Items beyond the blocks (every block is already an item); an item named
  /// like a block replaces that block's item.
  final List<ItemType> items;

  /// Crafting recipes.
  final List<Recipe> recipes;

  /// The player.
  final PlayerSpec player;

  /// The creatures.
  final List<MobSpec> mobs;

  /// Day, night and the light between.
  final SkySpec sky;

  /// Sound effects and music.
  final SoundSpec sounds;

  /// Circuits, or null for none.
  final SignalSpec? signals;

  /// The world seed.
  final int seed;

  /// How many chunks are streamed around the player.
  final int renderDistance;

  /// How long blocks take to break.
  final MiningRules mining;

  /// How each liquid kind flows (water and lava have defaults).
  final Map<String, LiquidSpec> liquids;

  /// Game logic run every step after the game's own.
  final List<GameSystem> systems;

  /// After the player breaks a block (by name) at a cell.
  final void Function(VoxelGame game, String block, IVec3 cell)? onBlockBroken;

  /// After the player places a block (by name) at a cell.
  final void Function(VoxelGame game, String block, IVec3 cell)? onBlockPlaced;

  /// After a mob dies.
  final void Function(VoxelGame game, Mob mob)? onMobKilled;

  /// After every simulation step.
  final void Function(VoxelGame game, double dt)? onTick;

  /// This game with the given fields replaced: the same world at another
  /// render distance, say, or with a hook of a test's.
  VoxelGameSpec copyWith({
    List<BlockType>? blocks,
    WorldGenSpec? world,
    List<ItemType>? items,
    List<Recipe>? recipes,
    PlayerSpec? player,
    List<MobSpec>? mobs,
    SkySpec? sky,
    SoundSpec? sounds,
    SignalSpec? signals,
    int? seed,
    int? renderDistance,
    MiningRules? mining,
    Map<String, LiquidSpec>? liquids,
    List<GameSystem>? systems,
    void Function(VoxelGame game, String block, IVec3 cell)? onBlockBroken,
    void Function(VoxelGame game, String block, IVec3 cell)? onBlockPlaced,
    void Function(VoxelGame game, Mob mob)? onMobKilled,
    void Function(VoxelGame game, double dt)? onTick,
  }) =>
      VoxelGameSpec(
        blocks: blocks ?? this.blocks,
        world: world ?? this.world,
        items: items ?? this.items,
        recipes: recipes ?? this.recipes,
        player: player ?? this.player,
        mobs: mobs ?? this.mobs,
        sky: sky ?? this.sky,
        sounds: sounds ?? this.sounds,
        signals: signals ?? this.signals,
        seed: seed ?? this.seed,
        renderDistance: renderDistance ?? this.renderDistance,
        mining: mining ?? this.mining,
        liquids: liquids ?? this.liquids,
        systems: systems ?? this.systems,
        onBlockBroken: onBlockBroken ?? this.onBlockBroken,
        onBlockPlaced: onBlockPlaced ?? this.onBlockPlaced,
        onMobKilled: onMobKilled ?? this.onMobKilled,
        onTick: onTick ?? this.onTick,
      );

  /// The block registry: [blocks] with air first.
  BlockRegistry<BlockType> buildBlocks() => BlockRegistry([
        if (blocks.isEmpty || blocks.first.id != 'air') const BlockType('air', color: 0, solid: false, hardness: -1, drop: ''),
        ...blocks,
      ]);

  /// The item registry: an item per holdable block, then [items] (replacing a
  /// block's item of the same id).
  ItemRegistry<ItemType> buildItems(BlockRegistry<BlockType> registry) {
    final byId = <String, ItemType>{
      for (final i in ItemRegistry.forBlocks(registry)) i.id: i,
    };
    for (final i in items) {
      byId[i.id] = i;
    }
    return ItemRegistry(byId.values);
  }
}
