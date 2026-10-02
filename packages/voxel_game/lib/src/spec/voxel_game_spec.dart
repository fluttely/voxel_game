import 'package:flutter/foundation.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/worldgen.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../mobs/mob.dart';
import '../mobs/mob_spec.dart';
import '../player/player_spec.dart';
import '../world/game_world.dart';
import 'graphics_spec.dart';
import 'screen_spec.dart';
import 'signal_spec.dart';
import 'sky_spec.dart';
import 'sound_spec.dart';
import 'touch_controls_spec.dart';

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
    this.effects = const [],
    this.player = const PlayerSpec(),
    this.mobs = const [],
    this.sky = const SkySpec(),
    this.sounds = const SoundSpec(),
    this.signals,
    this.seed = 1,
    this.renderDistance = 6,
    this.graphics,
    this.touchControls = TouchControlsSpec.standard,
    this.screens = const {},
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

  /// The status effects there are: what a `Food` starts, what the player
  /// carries in `PlayerEntity.effects`.
  final List<EffectType> effects;

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

  /// How many chunks are streamed around the player: the default of the
  /// player's `GameSettings.renderDistance`, which the world streams.
  final int renderDistance;

  /// How the world is drawn; null for [GraphicsSpec.phone] on iOS and Android
  /// and [GraphicsSpec.desktop] everywhere else.
  final GraphicsSpec? graphics;

  /// The controls a finger plays with, shown while the last device was a
  /// finger; null for a game that draws its own (the default HUD's hotbar then
  /// takes no finger either).
  final TouchControlsSpec? touchControls;

  /// The game's own screens, by the id a `DeclaredScreen` opens; those with a
  /// `ScreenSpec.menu` are listed in the game menu, in this order.
  final Map<String, ScreenSpec> screens;

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
  ///
  /// A field that may be null is given as a getter of its new value, so null
  /// can be asked for: `copyWith(touchControls: () => null)` takes the kit's
  /// controls away, and leaving `touchControls` out keeps them.
  VoxelGameSpec copyWith({
    List<BlockType>? blocks,
    WorldGenSpec? world,
    List<ItemType>? items,
    List<Recipe>? recipes,
    List<EffectType>? effects,
    PlayerSpec? player,
    List<MobSpec>? mobs,
    SkySpec? sky,
    SoundSpec? sounds,
    ValueGetter<SignalSpec?>? signals,
    int? seed,
    int? renderDistance,
    ValueGetter<GraphicsSpec?>? graphics,
    ValueGetter<TouchControlsSpec?>? touchControls,
    Map<String, ScreenSpec>? screens,
    MiningRules? mining,
    Map<String, LiquidSpec>? liquids,
    List<GameSystem>? systems,
    ValueGetter<void Function(VoxelGame game, String block, IVec3 cell)?>? onBlockBroken,
    ValueGetter<void Function(VoxelGame game, String block, IVec3 cell)?>? onBlockPlaced,
    ValueGetter<void Function(VoxelGame game, Mob mob)?>? onMobKilled,
    ValueGetter<void Function(VoxelGame game, double dt)?>? onTick,
  }) => VoxelGameSpec(
    blocks: blocks ?? this.blocks,
    world: world ?? this.world,
    items: items ?? this.items,
    recipes: recipes ?? this.recipes,
    effects: effects ?? this.effects,
    player: player ?? this.player,
    mobs: mobs ?? this.mobs,
    sky: sky ?? this.sky,
    sounds: sounds ?? this.sounds,
    signals: signals == null ? this.signals : signals(),
    seed: seed ?? this.seed,
    renderDistance: renderDistance ?? this.renderDistance,
    graphics: graphics == null ? this.graphics : graphics(),
    touchControls: touchControls == null ? this.touchControls : touchControls(),
    screens: screens ?? this.screens,
    mining: mining ?? this.mining,
    liquids: liquids ?? this.liquids,
    systems: systems ?? this.systems,
    onBlockBroken: onBlockBroken == null ? this.onBlockBroken : onBlockBroken(),
    onBlockPlaced: onBlockPlaced == null ? this.onBlockPlaced : onBlockPlaced(),
    onMobKilled: onMobKilled == null ? this.onMobKilled : onMobKilled(),
    onTick: onTick == null ? this.onTick : onTick(),
  );

  /// The block registry: [blocks] with air first.
  BlockRegistry<BlockType> buildBlocks() => BlockRegistry([
    if (blocks.isEmpty || blocks.first.id != 'air')
      const BlockType('air', color: 0, solid: false, hardness: -1, drop: ''),
    ...blocks,
  ]);

  /// The item registry: an item per holdable block, then [items] (replacing a
  /// block's item of the same id). Throws [ArgumentError] for a food whose
  /// effect is not in [effects] or which leaves an unknown item, for armour
  /// worn in a slot the player does not have, for a block whose loot (or its
  /// store's) names an unknown item, for a bucket that scoops or pours a liquid there is
  /// not or becomes an unknown item, and for an item the kit cannot draw: a tool with no
  /// stock shape and none declared, a block's shape on an item that places none.
  ItemRegistry<ItemType> buildItems(BlockRegistry<BlockType> registry) {
    final byId = <String, ItemType>{for (final i in ItemRegistry.forBlocks(registry)) i.id: i};
    for (final i in items) {
      byId[i.id] = i;
    }
    for (final b in registry.types) {
      for (final e in [...?b.loot?.entries, ...?b.storage?.loot?.entries]) {
        if (!byId.containsKey(e.item)) throw ArgumentError.value(e.item, b.id, 'the block holds an item that does not exist');
      }
    }
    final effectIds = {for (final e in effects) e.id};
    for (final i in byId.values) {
      if (ItemModel.shapeOf(i) == ItemShape.block && i.block == null) {
        throw ArgumentError.value(i.id, 'item', 'a block\'s shape on an item that places no block');
      }
      final food = i.food, armor = i.armor;
      if (food?.effect case final e? when !effectIds.contains(e)) {
        throw ArgumentError.value(e, i.id, 'the food starts an effect the spec does not declare');
      }
      if (food?.leaves case final l? when !byId.containsKey(l)) {
        throw ArgumentError.value(l, i.id, 'the food leaves an item that does not exist');
      }
      if (armor != null && !player.armorSlots.contains(armor.slot)) {
        throw ArgumentError.value(armor.slot, i.id, 'the armour is worn in a slot the player does not have');
      }
      final bucket = i.bucket;
      if (bucket == null) continue;
      for (final e in bucket.fills.entries) {
        if (!registry.liquidKinds.contains(e.key)) throw ArgumentError.value(e.key, i.id, 'the bucket scoops no liquid');
        if (!byId.containsKey(e.value)) throw ArgumentError.value(e.value, i.id, 'the bucket fills into no item');
      }
      if (bucket.liquid case final l?) {
        if (!registry.has(l) || !registry[registry.indexOf(l)].isLiquid || !registry[registry.indexOf(l)].liquidSource) {
          throw ArgumentError.value(l, i.id, 'the bucket pours what is not a liquid source');
        }
        if (!byId.containsKey(bucket.empties)) throw ArgumentError.value(bucket.empties, i.id, 'the bucket empties into no item');
      }
    }
    return ItemRegistry(byId.values);
  }

  /// Every effect in [effects], by id; throws [ArgumentError] on a duplicate.
  Map<String, EffectType> buildEffects() {
    final byId = <String, EffectType>{};
    for (final e in effects) {
      if (byId.containsKey(e.id)) throw ArgumentError('duplicate effect id: ${e.id}');
      byId[e.id] = e;
    }
    return byId;
  }
}
