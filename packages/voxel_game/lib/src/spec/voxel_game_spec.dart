import 'package:flutter/foundation.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/worldgen.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../entities/projectile.dart';
import '../mobs/behaviors.dart';
import '../mobs/mob.dart';
import '../mobs/mob_spec.dart';
import '../player/player_spec.dart';
import '../fishing/fishing_spec.dart';
import '../vehicles/vehicle_spec.dart';
import '../world/game_world.dart';
import 'graphics_spec.dart';
import 'portal_spec.dart';
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
    this.dimensions = const {},
    this.portals = const [],
    this.items = const [],
    this.recipes = const [],
    this.effects = const [],
    this.player = const PlayerSpec(),
    this.mobs = const [],
    this.vehicles = const [],
    this.fishing,
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

  /// How the world is generated: the dimension a game starts in, whose id
  /// is [mainDimension].
  final WorldGenSpec world;

  /// The id of the dimension [world] generates.
  static const String mainDimension = 'world';

  /// The other dimensions, by id: each a world of its own, generated from the
  /// same seed, reached through [portals] or `VoxelGame.travel`. Their order
  /// numbers them after [world] (see [dimensionIds]).
  final Map<String, WorldGenSpec> dimensions;

  /// The gateways between dimensions.
  final List<PortalSpec> portals;

  /// Every dimension's id, numbered as the world streams them: [mainDimension]
  /// first, then [dimensions] in order.
  List<String> get dimensionIds => [mainDimension, ...dimensions.keys];

  /// Every dimension's generation, numbered as [dimensionIds].
  List<WorldGenSpec> get dimensionWorlds => [world, ...dimensions.values];

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

  /// The vehicles, one an item: a `BoatSpec`'s boat is put on water with its
  /// item in hand, a `CartSpec`'s minecart on a rail; each is ridden by a
  /// use, left with sneak and broken back into its item by a swing (see
  /// [checkVehicles]).
  final List<VehicleSpec> vehicles;

  /// How the player fishes: the rod, what bites, where; null for a game with
  /// no fishing (see [checkFishing]).
  final FishingSpec? fishing;

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
    Map<String, WorldGenSpec>? dimensions,
    List<PortalSpec>? portals,
    List<ItemType>? items,
    List<Recipe>? recipes,
    List<EffectType>? effects,
    PlayerSpec? player,
    List<MobSpec>? mobs,
    List<VehicleSpec>? vehicles,
    ValueGetter<FishingSpec?>? fishing,
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
    dimensions: dimensions ?? this.dimensions,
    portals: portals ?? this.portals,
    items: items ?? this.items,
    recipes: recipes ?? this.recipes,
    effects: effects ?? this.effects,
    player: player ?? this.player,
    mobs: mobs ?? this.mobs,
    vehicles: vehicles ?? this.vehicles,
    fishing: fishing == null ? this.fishing : fishing(),
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
        if (!byId.containsKey(e.item)) {
          throw ArgumentError.value(e.item, b.id, 'the block holds an item that does not exist');
        }
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
        if (!registry.liquidKinds.contains(e.key)) {
          throw ArgumentError.value(e.key, i.id, 'the bucket scoops no liquid');
        }
        if (!byId.containsKey(e.value)) throw ArgumentError.value(e.value, i.id, 'the bucket fills into no item');
      }
      if (bucket.liquid case final l?) {
        if (!registry.has(l) ||
            !registry[registry.indexOf(l)].isLiquid ||
            !registry[registry.indexOf(l)].liquidSource) {
          throw ArgumentError.value(l, i.id, 'the bucket pours what is not a liquid source');
        }
        if (!byId.containsKey(bucket.empties)) {
          throw ArgumentError.value(bucket.empties, i.id, 'the bucket empties into no item');
        }
      }
    }
    return ItemRegistry(byId.values);
  }

  /// Throws [ArgumentError] for two mobs of one id, and for a mob whose loot
  /// names an item not in [items], that splits into a mob not declared, whose
  /// strike or shot (a `RangedAttack`'s `ProjectileSpec.onHit`) leaves an
  /// effect not in [effects], that is worth experience
  /// when the player gains none (`PlayerSpec.xp`), that is tamed with an
  /// unknown item, at a chance outside (0, 1], or with no `tamedBrain`,
  /// and for a ghost that does not fly.
  void checkMobs(ItemRegistry<ItemType> items) {
    final ids = <String>{};
    for (final m in mobs) {
      if (!ids.add(m.id)) throw ArgumentError.value(m.id, 'mobs', 'two mobs of one id');
    }
    final effectIds = {for (final e in effects) e.id};
    for (final m in mobs) {
      for (final e in m.loot.entries) {
        if (!items.has(e.item)) throw ArgumentError.value(e.item, m.id, 'the mob drops an item that does not exist');
      }
      if (m.splitsInto case final split? when !ids.contains(split.mob)) {
        throw ArgumentError.value(split.mob, m.id, 'the mob splits into a mob not declared');
      }
      if (m.onHit case final hit? when !effectIds.contains(hit.effect)) {
        throw ArgumentError.value(hit.effect, m.id, 'the mob\'s strike leaves an effect the spec does not declare');
      }
      for (final b in [...m.brain, ...m.tamedBrain]) {
        if (b case RangedAttack(projectile: ProjectileSpec(onHit: final hit?)) when !effectIds.contains(hit.effect)) {
          throw ArgumentError.value(hit.effect, m.id, 'the mob\'s shot leaves an effect the spec does not declare');
        }
      }
      for (final item in m.tameWith) {
        if (!items.has(item)) {
          throw ArgumentError.value(item, m.id, 'the mob is tamed with an item that does not exist');
        }
      }
      if (m.tameWith.isNotEmpty && m.tamedBrain.isEmpty) {
        throw ArgumentError.value(m.id, 'tamedBrain', 'a mob that is tamed needs a brain to think with then');
      }
      if (m.tameChance <= 0.0 || m.tameChance > 1.0) {
        throw ArgumentError.value(m.tameChance, m.id, 'the chance to tame is above 0 and at most 1');
      }
      if (m.ghost && m.gait != Gait.fly) {
        throw ArgumentError.value(m.gait, m.id, 'a ghost flies: nothing under it holds it up');
      }
      if (m.xp > 0 && player.xp == null) {
        throw ArgumentError.value(m.xp, m.id, 'the mob is worth experience and the player gains none');
      }
    }
  }

  /// Throws [ArgumentError] for music ([SoundSpec.music]) naming a track it
  /// has not, a biome no dimension's world has, or a dimension not declared.
  void checkMusic() => sounds.music?.check(
    biomeNames: {
      for (final w in dimensionWorlds) ...[for (final b in w.biomes) b.name, ?w.ocean?.name, ?w.beach?.name],
    },
    dimensionIds: dimensionIds,
  );

  /// Throws [ArgumentError] for [fishing] with a rod that is no item or
  /// places a block, a catch that is no item or a one-of table whose chances
  /// sum over 1 (`LootTable.check`), a liquid kind no block of [blocks] is,
  /// and experience for a catch with no `PlayerSpec.xp` declared.
  void checkFishing(BlockRegistry<BlockType> blocks, ItemRegistry<ItemType> items) {
    final f = fishing;
    if (f == null) return;
    if (!items.has(f.rod)) throw ArgumentError.value(f.rod, 'fishing', 'the rod is no item');
    if (items[f.rod].block != null) throw ArgumentError.value(f.rod, 'fishing', 'the rod places a block');
    for (final e in f.catches.entries) {
      if (!items.has(e.item)) throw ArgumentError.value(e.item, 'fishing', 'a catch is no item');
    }
    f.catches.check();
    for (final l in f.liquids) {
      if (!blocks.liquidKinds.contains(l)) throw ArgumentError.value(l, 'fishing', 'no block is that liquid');
    }
    if (f.xp > 0 && player.xp == null) {
      throw ArgumentError.value(f.xp, 'fishing', 'a catch gives experience only with PlayerSpec.xp declared');
    }
  }

  /// Throws [ArgumentError] for a vehicle whose item is not in [items] or
  /// places a block (a use with it in hand would build instead), and for two
  /// vehicles of one item.
  void checkVehicles(ItemRegistry<ItemType> items) {
    final seen = <String>{};
    for (final v in vehicles) {
      if (!items.has(v.item)) throw ArgumentError.value(v.item, 'vehicles', 'the vehicle\'s item does not exist');
      if (!seen.add(v.item)) throw ArgumentError.value(v.item, 'vehicles', 'two vehicles of one item');
      if (items[v.item].block != null) {
        throw ArgumentError.value(v.item, 'vehicles', 'the vehicle\'s item places a block');
      }
    }
  }

  /// Throws [ArgumentError] for a dimension named [mainDimension], and for a
  /// portal between dimensions not declared (or one and the same), of blocks
  /// not in [registry], a solid portal block or one another portal has, or a
  /// lighter not in [items].
  void checkDimensions(BlockRegistry<BlockType> registry, ItemRegistry<ItemType> items) {
    if (dimensions.containsKey(mainDimension)) {
      throw ArgumentError.value(mainDimension, 'dimensions', 'the main world is `world`, not a dimension');
    }
    final ids = dimensionIds;
    final portalBlocks = <String>{};
    for (final p in portals) {
      if (!portalBlocks.add(p.portal)) throw ArgumentError.value(p.portal, 'portal', 'two portals of one block');
      for (final end in [p.from, p.to]) {
        if (!ids.contains(end)) throw ArgumentError.value(end, 'portal', 'no such dimension');
      }
      if (p.from == p.to) throw ArgumentError.value(p.to, 'portal', 'a portal leads to another dimension');
      for (final b in [p.frame, p.portal]) {
        if (!registry.has(b)) throw ArgumentError.value(b, 'portal', 'no such block');
      }
      if (registry[registry.indexOf(p.portal)].solid) {
        throw ArgumentError.value(p.portal, 'portal', 'a portal block must not be solid: a body stands in it');
      }
      if (!items.has(p.lighter)) throw ArgumentError.value(p.lighter, 'portal', 'no such item');
    }
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
