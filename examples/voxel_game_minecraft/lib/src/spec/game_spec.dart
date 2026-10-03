import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:voxel_game/voxel_game.dart';

import '../player/heartbeat.dart';
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
/// What only this game has (classes, quests, the bosses and their structures,
/// villagers' trades, the map) comes in as its own systems and screens on top
/// (VA-Zj to VA-Zl).
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
    xp: XpSpec(),
    critChance: 0.1,
  ),
  mobs: mobTable,
  // The player's heart is heard while its health is low.
  systems: _systems,
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

List<GameSystem> _systems() => [Heartbeat()];

bool get _phone => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
