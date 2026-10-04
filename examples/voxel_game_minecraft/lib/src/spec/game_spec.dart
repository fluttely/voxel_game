import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:voxel_game/voxel_game.dart';

import '../classes/class_system.dart';
import '../classes/class_table.dart';
import '../enchanting/enchanting.dart';
import '../journal/achievements.dart';
import '../journal/bestiary.dart';
import '../journal/game_stats.dart';
import '../journal/journal_screen.dart';
import '../journal/quest_log.dart';
import '../journal/stats_screen.dart';
import '../journal/tutorial.dart';
import '../map/map_screen.dart';
import '../map/world_map.dart';
import '../player/heartbeat.dart';
import '../playground/playground.dart';
import '../playground/playground_screen.dart';
import '../structures/structures.dart';
import '../ui/controls_screen.dart';
import '../villages/trade_screen.dart';
import '../villages/villages.dart';
import '../waypoints/waypoints.dart';
import 'block_table.dart';
import 'effect_table.dart';
import 'game_sounds.dart';
import 'item_table.dart';
import 'mob_table.dart';
import 'recipe_table.dart';
import 'world_table.dart';

/// The game, declared for the kit: its blocks, items, recipes and effects, its
/// world and the underworld a portal leads to, circuits, creatures, vehicles,
/// fishing, the sky and the weather, sounds and music, and the player.
///
/// The player is the class the world was made with (`classPlayer`, the
/// title's `classOption`): its abilities on R and F, a dodge on Alt and its
/// talents in the journal on J (`ClassSystem`, `JournalScreen`).
///
/// The journal keeps the quests, the achievements and the creatures met
/// (`QuestLog`, `Achievements`, `Bestiary`); the game menu has the stats
/// (`GameStats`) and the controls (F1); a new world made with the tutorial
/// walks the player through their first steps (`Tutorial`, F6 skips it).
///
/// A waypoint placed is listed in the journal, and using one travels to
/// another (`Waypoints`); an enchanting table adds to the bonus of the weapon
/// or tool in hand (`Enchanting`).
///
/// A village the player comes near is peopled with villagers, whose use opens
/// their trades (`Villages`, `TradeScreen`).
///
/// The structures met are found and told; the temple, the dungeon and the
/// underworld's fortress wake their bosses, the fortress core is sealed
/// until its lord dies, spawner blocks bring creatures and ruins are haunted
/// at night (`Structures`).
///
/// M cycles the map (`WorldMap`): the minimap in the HUD's corner, then the
/// whole map (`MapScreen`), then neither; it draws the chunks explored, the
/// structures found, the waypoints and the creatures.
///
/// A playground (the title's `playgroundOption`) presses a flat plaza
/// into the world (`Playground.worldFor`) and lays nine exhibits on it
/// (`Playground`), each with its card (`ZoneCard`); F7, F8 and F9 change its
/// weather, its time of day and rebuild an exhibit, and so do the buttons of
/// Playground in its game menu (`PlaygroundScreen`).
final VoxelGameSpec gameSpec = VoxelGameSpec(
  seed: 1337,
  blocks: blockTable,
  items: itemTable,
  recipes: recipeTable,
  effects: effectTable,
  shots: shots,
  // Shears cut leaves at once and get the leaves.
  mining: const MiningRules(
    cuts: {
      'shears': {'leaves'},
    },
  ),
  world: overworld,
  worldFor: Playground.worldFor,
  dimensions: const {'underworld': underworld},
  // An obsidian frame around a hollow two wide and three tall, lit with flint and steel; two seconds in it and
  // the player crosses, a frame built on the far side for the way back.
  portals: const [PortalSpec(frame: 'obsidian', portal: 'portal', lighter: 'flint_and_steel', to: 'underworld')],
  structureLoot: structureLootTable,
  // Circuits: a lever, a button (a second) or a plate under a body powers a wire, and what it touches answers —
  // a lamp lights, an iron door opens, a piston pushes, a run of powered rails lights up, TNT is lit.
  signals: const SignalSpec(
    wire: ('wire_off', 'wire_on'),
    levers: {'lever_off': 'lever_on'},
    buttons: {'button': ('button_on', 1.0)},
    plates: {'pressure_plate'},
    lamps: {'redstone_lamp_off': 'redstone_lamp_on'},
    doors: {'iron_door_z': 'iron_door_z_open', 'iron_door_x': 'iron_door_x_open'},
    explosives: {'tnt': Explosive()},
    pistons: {
      'piston_n': 'piston_n_on',
      'piston_e': 'piston_e_on',
      'piston_s': 'piston_s_on',
      'piston_w': 'piston_w_on',
    },
    poweredRails: {'powered_rail_ns': 'powered_rail_ns_on', 'powered_rail_ew': 'powered_rail_ew_on'},
  ),
  // Rain and storms rolled every few minutes, snow where it is cold, none in the desert; the underworld has no
  // sun, a dark red sky and a haze closing in.
  sky: const SkySpec(
    weather: WeatherSpec(),
    dimensions: {
      'underworld': DimensionSky(
        StillSky(zenith: 0x0F0303, horizon: 0x470D08, ground: 0x1F0505, ambient: 0xFF8C6B),
        haze: Haze(0x4C0F0A, 0.014),
      ),
    },
  ),
  sounds: gameSounds,
  player: const PlayerSpec(
    startingItems: {'wooden_pickaxe': 1, 'wooden_axe': 1, 'apple': 5, 'torch': 8},
    hunger: HungerSpec(),
    xp: XpSpec(hpPerLevel: 3.0),
    critChance: 0.1,
  ),
  playerFor: classPlayer,
  mobs: mobTable,
  // The player's heart is heard while its health is low; the class plays its abilities, stamina and mana; the
  // journal counts what the player does, the quests and the achievements on it, and the tutorial watches.
  systems: _systems,
  // The class's two abilities, the dodge, the journal, the map, the controls, a skip of the tutorial, and a
  // playground's three.
  actions: const [
    ActionSpec('ability', keys: [PhysicalKeyboardKey.keyR], gamepad: [GamepadButton.leftBumper], touch: Icons.flash_on),
    ActionSpec(
      'ability2',
      keys: [PhysicalKeyboardKey.keyF],
      gamepad: [GamepadButton.rightBumper],
      touch: Icons.auto_awesome,
    ),
    ActionSpec(
      'dodge',
      keys: [PhysicalKeyboardKey.altLeft, PhysicalKeyboardKey.altRight],
      gamepad: [GamepadButton.x],
      touch: Icons.double_arrow,
    ),
    ActionSpec('journal', keys: [PhysicalKeyboardKey.keyJ], gamepad: [GamepadButton.touchpad], touch: Icons.menu_book),
    ActionSpec(WorldMap.action, keys: [PhysicalKeyboardKey.keyM], gamepad: [GamepadButton.back], touch: Icons.map),
    ActionSpec('controls', keys: [PhysicalKeyboardKey.f1], gamepad: [GamepadButton.home]),
    ActionSpec(Tutorial.skipAction, keys: [PhysicalKeyboardKey.f6], gamepad: [GamepadButton.dpadLeft]),
    // A pad and a phone reach these through the game menu (`PlaygroundScreen`).
    ActionSpec(Playground.weatherAction, keys: [PhysicalKeyboardKey.f7]),
    ActionSpec(Playground.timeAction, keys: [PhysicalKeyboardKey.f8]),
    ActionSpec(Playground.rebuildAction, keys: [PhysicalKeyboardKey.f9]),
  ],
  // A waypoint lists the others, to travel to one; an enchanting table enchants what is in hand.
  blockUses: const {Waypoints.block: Waypoints.open, Enchanting.table: _enchant},
  // A villager opens its trades; a client asks the host for them.
  mobUses: const {Villages.villager: Villages.use},
  messages: const {Villages.askMessage: Villages.heardAsk, Villages.offersMessage: Villages.heardOffers},
  screens: const {
    'journal': ScreenSpec(JournalScreen.builder, menu: 'Journal', action: 'journal'),
    Waypoints.screen: ScreenSpec(JournalScreen.waypointsBuilder),
    Villages.screen: ScreenSpec(TradeScreen.builder),
    WorldMap.screen: ScreenSpec(MapScreen.builder, menu: 'Map'),
    'stats': ScreenSpec(StatsScreen.builder, menu: 'Stats'),
    'controls': ScreenSpec(ControlsScreen.builder, menu: 'Controls', action: 'controls'),
    Playground.screen: ScreenSpec(PlaygroundScreen.builder, menu: 'Playground', listed: PlaygroundScreen.listed),
  },
  vehicles: const [
    BoatSpec(item: 'boat'),
    CartSpec(item: 'minecart'),
  ],
  // A bite answered in time: mostly a fish, now and then a salmon, some junk, and once in twenty a treasure.
  fishing: const FishingSpec(
    rod: 'fishing_rod',
    catches: LootTable.oneOf([
      LootEntry('raw_fish', 1, 1, 0.70),
      LootEntry('raw_salmon', 1, 1, 0.10),
      LootEntry('stick', 1, 1, 0.05),
      LootEntry('bone', 1, 1, 0.05),
      LootEntry('leather', 1, 1, 0.05),
      LootEntry('magic_dust', 1, 1, 0.02),
      LootEntry('gem_shard', 1, 1, 0.02),
      LootEntry('iron_sword', 1, 1, 0.01),
    ]),
  ),
  // V turns the view and F5 flies, in a Creative world.
  bindings: VoxelAction.defaultBindings.rebind(
    keys: {
      VoxelAction.toggleView: [PhysicalKeyboardKey.keyV],
      VoxelAction.fly: [PhysicalKeyboardKey.f5],
    },
  ),
  // A frame is held back while the GPU is busy, which keeps the menus' text whole (`GpuPacedScene`).
  graphics: (_phone ? GraphicsSpec.phone : GraphicsSpec.desktop).copyWith(paced: true),
);

// The stats before what reads them: the achievements count what they counted in the same step.
List<GameSystem> _systems() => [
  Heartbeat(),
  ClassSystem(),
  GameStats(),
  Bestiary(),
  QuestLog(),
  Achievements(),
  Tutorial(),
  Waypoints(),
  Villages(),
  Structures(),
  WorldMap(),
  Playground(),
];

void _enchant(VoxelGame game, IVec3 cell) => Enchanting.use(game, cell);

bool get _phone => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
