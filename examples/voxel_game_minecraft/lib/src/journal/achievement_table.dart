import 'package:voxel_game/voxel_game.dart';

import '../classes/class_system.dart';
import '../spec/mob_table.dart';
import 'achievement.dart';
import 'game_stats.dart';

/// The game's achievements, in the journal's order. `traveler` is unlocked
/// by a trip to a waypoint (`Waypoints.travel`), `underworld` by the
/// fortress (VA-Zl3).
const List<Achievement> achievementTable = [
  Achievement('first_block', 'Getting Wood', 'Break your first block', on: _broke),
  Achievement('builder', 'Builder', 'Place 100 blocks', when: _built),
  Achievement('first_kill', 'Monster Hunter', 'Defeat your first monster', on: _killedMonster),
  Achievement('slayer', 'Slayer', 'Defeat 50 monsters', when: _slew),
  Achievement('level_5', 'Adventurer', 'Reach level 5', when: _level5),
  Achievement('level_10', 'Hero', 'Reach level 10', when: _level10),
  Achievement('diamonds', 'Diamonds!', 'Pick up a diamond', on: _pickedDiamond),
  Achievement('boss', 'Boss Slayer', 'Defeat a boss', on: _killedBoss),
  Achievement('elite', 'Elite Hunter', 'Defeat an elite monster', on: _killedElite),
  Achievement('crafter', 'Crafter', 'Craft 25 items', when: _crafted),
  Achievement('sleeper', 'Good Night', 'Sleep in a bed', on: _slept),
  Achievement('sailor', 'Sailor', 'Board a boat', on: _boarded),
  Achievement('deep', 'Deep Down', 'Go below height 20', when: _deep),
  Achievement('brewer', 'Brewer', 'Drink a potion', on: _drank),
  Achievement('talent', 'Gifted', 'Spend a talent point', when: _learned),
  Achievement('traveler', 'Traveler', 'Teleport through a waypoint'),
  Achievement('tamer', 'Best Friend', 'Tame a wolf', on: _tamed),
  Achievement('glider', 'Wingsuit', 'Glide for the first time', when: _gliding),
  Achievement('fisher', 'Gone Fishing', 'Catch your first fish', on: _caught),
  Achievement('rider', 'Saddle Up', 'Ride a horse', on: _mounted),
  Achievement('underworld', 'Into the Fire', 'Find a fortress in the underworld'),
  Achievement('heart', 'Heart of the Underworld', 'Take the underworld heart', on: _pickedHeart),
];

/// The achievement [id]; throws for none.
Achievement achievementById(String id) => achievementTable.firstWhere(
  (a) => a.id == id,
  orElse: () => throw ArgumentError.value(id, 'id', 'no such achievement'),
);

/// The height under which the player is deep down, in the main world.
const double deepUnder = 20.0;

bool _broke(VoxelGame game, GameEvent e) => e is BlockBroken;

bool _built(VoxelGame game) => GameStats.of(game).blocksPlaced >= 100;

bool _killedMonster(VoxelGame game, GameEvent e) => e is MobKilled && e.byPlayer && isMonster(e.mob.spec);

// Every creature counts toward the fifty, as the old game's did.
bool _slew(VoxelGame game) => GameStats.of(game).kills >= 50;

bool _level5(VoxelGame game) => game.player.level >= 5;

bool _level10(VoxelGame game) => game.player.level >= 10;

bool _pickedDiamond(VoxelGame game, GameEvent e) => e is ItemPickedUp && e.item == 'diamond';

bool _killedBoss(VoxelGame game, GameEvent e) => e is MobKilled && e.byPlayer && e.mob.spec.boss;

bool _killedElite(VoxelGame game, GameEvent e) => e is MobKilled && e.byPlayer && isElite(e.mob.spec.id);

bool _crafted(VoxelGame game) => GameStats.of(game).crafted >= 25;

bool _slept(VoxelGame game, GameEvent e) => e is Slept;

bool _boarded(VoxelGame game, GameEvent e) => e is Boarded && e.vehicle is Boat;

bool _deep(VoxelGame game) =>
    game.dimension == VoxelGameSpec.mainDimension && !game.player.isDead && game.player.position.y < deepUnder;

bool _drank(VoxelGame game, GameEvent e) => e is FoodEaten && e.item.endsWith('_potion');

bool _learned(VoxelGame game) => ClassSystem.of(game).ranks.isNotEmpty;

// A companion: a creature tamed that is not ridden.
bool _tamed(VoxelGame game, GameEvent e) => e is Tamed && e.species.mount == null;

bool _gliding(VoxelGame game) => game.player.gliding;

bool _caught(VoxelGame game, GameEvent e) => e is Caught && e.stacks.isNotEmpty;

bool _mounted(VoxelGame game, GameEvent e) => e is Mounted;

bool _pickedHeart(VoxelGame game, GameEvent e) => e is ItemPickedUp && e.item == 'underworld_heart';
