import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart' show ChunkStreamer;
import 'package:voxel_game/voxel_game.dart';

import '../journal/achievements.dart';
import '../spec/world_table.dart';
import 'fortress.dart';

/// What was done at a structure, once each, kept in the save.
enum StructureMark {
  /// The player came within [Structures.foundWithin]: the map draws it.
  found,

  /// Its notice was given (`Structures.minorStructureFound`, the fortress's).
  told,

  /// Its boss woke: the temple's mummy king, the dungeon's troll, the
  /// fortress's lord.
  boss,

  /// The fortress's blazes woke.
  blazes,
}

/// The world's structures as the player meets them, a look a second about
/// the player's chunk (`structuresNear`), on the authority only. Within
/// [foundWithin] of one it is found (the map, VA-Zl4); within [toldWithin]
/// of a ruin, a well, a mine or a temple, a notice tells it
/// ([minorStructureFound]).
///
/// The bosses wake once each, where the player first comes near: the mummy
/// king within [kingWakesWithin] of the temple's chamber, the troll within
/// [trollWakesWithin] of the dungeon's last room. The underworld's fortress
/// ([fortress]) is told within [foundWithin] (and unlocks `underworld`), two
/// blazes wake within [blazesWakeWithin] of its hall's middle, and its lord
/// within [lordWakesWithin] of its core. The core is sealed ([sealedCore])
/// until the lord dies, and then swapped for one that can be mined
/// ([openCore]); the lord carries its core on itself (`Mob.data`, under
/// [coreKey]), and he and the king are kept by the save (`persistent`).
///
/// A dungeon's or a mine's spawner block within [spawnerReach] brings one of
/// [spawnerBrood] beside it, one look in [spawnerSkip] skipped, while fewer
/// than [crowdMost] creatures are within [crowdWithin] of it. At night a
/// ruin within [hauntReach] is haunted: a ghost by it at [hauntChance] a
/// look, while fewer than [ghostsMost] are within [ghostsWithin].
///
/// Saved with the world (under `structures`): what was done where.
class Structures extends SavedSystem {
  /// The key of the structures in the save.
  static const String key = 'structures';

  /// Seconds between two looks.
  static const double lookEvery = 1.0;

  /// Metres from a structure's site within which it is found.
  static const double foundWithin = 48.0;

  /// Metres from a minor structure's site within which it is told.
  static const double toldWithin = 24.0;

  /// The notice of each minor structure, by name.
  static const Map<String, String> minorStructureFound = {
    'ruins': 'You found an old ruin!',
    'well': 'You found a well!',
    'mine': 'You found an abandoned mine!',
    'temple': 'You found a desert temple!',
  };

  /// Metres from the temple's chamber within which the mummy king wakes.
  static const double kingWakesWithin = 6.0;

  /// Metres from the dungeon's last room within which the troll wakes.
  static const double trollWakesWithin = 14.0;

  /// Metres from the fortress hall's middle within which its blazes wake.
  static const double blazesWakeWithin = 20.0;

  /// Metres from the fortress core within which the lord wakes.
  static const double lordWakesWithin = 14.0;

  /// The key of the lord's core in its `Mob.data`.
  static const String coreKey = 'core';

  /// What a spawner block brings.
  static const List<String> spawnerBrood = ['zombie', 'skeleton', 'spider', 'cave_slime'];

  /// Metres from a spawner block within which it brings creatures.
  static const double spawnerReach = 13.0;

  /// Metres from a spawner block within which creatures crowd it.
  static const double crowdWithin = 12.0;

  /// How many creatures crowd a spawner block.
  static const int crowdMost = 5;

  /// The share of a spawner block's looks that bring nothing.
  static const double spawnerSkip = 0.4;

  /// Metres from a ruin within which it is haunted at night.
  static const double hauntReach = 40.0;

  /// The share of a haunted ruin's looks that bring a ghost.
  static const double hauntChance = 0.35;

  /// How many ghosts a ruin keeps, and metres from it within which they count.
  static const int ghostsMost = 2;
  static const double ghostsWithin = 24.0;

  /// The structures of [game].
  static Structures of(VoxelGame game) => game.system<Structures>();

  final Map<_Site, Set<StructureMark>> _done = {};
  double _lookIn = 0.0;

  /// Whether [mark] was done at the structure [s] of [dimension].
  bool did(String dimension, PlacedStructure s, StructureMark mark) =>
      _done[_siteOf(dimension, s)]?.contains(mark) ?? false;

  /// The structures of [dimension] the player found.
  Iterable<PlacedStructure> foundIn(String dimension) => [
    for (final MapEntry(key: s, value: marks) in _done.entries)
      if (s.dimension == dimension && marks.contains(StructureMark.found)) (name: s.name, x: s.x, y: s.y, z: s.z),
  ];

  /// The plan of the fortress at [s] in [game]'s world.
  static FortressPlan fortressAt(VoxelGame game, PlacedStructure s) =>
      FortressPlan.of(s.x, s.z, (salt) => game.world.generator.hash(s.x, salt, s.z));

  @override
  void tick(VoxelGame game, double dt) {
    if (!game.authority) return;
    _lookIn -= dt;
    if (_lookIn > 0.0) return;
    _lookIn = lookEvery;
    final here = game.player.position;
    final chunk = ChunkStreamer.chunkOf(IVec3.floor(here));
    for (final s in game.world.generator.structuresNear(chunk.x, chunk.z)) {
      final site = _siteOf(game.dimension, s);
      final d = IVec3(s.x, s.y, s.z).distanceTo(here);
      if (d < foundWithin) _mark(site, StructureMark.found);
      final found = minorStructureFound[s.name];
      if (found != null && d < toldWithin && _mark(site, StructureMark.told)) game.notify(found);
      switch (s.name) {
        case 'temple':
          _temple(game, s, site);
        case 'dungeon':
          _dungeon(game, s, site);
        case 'mine':
          _mineSpawner(game, s);
        case 'ruins':
          _haunt(game, s);
        case 'fortress':
          _fortress(game, s, site, d);
      }
    }
  }

  /// Marks [mark] done at [site]: true the first time.
  bool _mark(_Site site, StructureMark mark) => (_done[site] ??= {}).add(mark);

  bool _has(_Site site, StructureMark mark) => _done[site]?.contains(mark) ?? false;

  // The mummy king, between the chests at the back of the chamber over the plate.
  void _temple(VoxelGame game, PlacedStructure s, _Site site) {
    final chamber = Vector3(s.x + 0.5, s.y + 1.0, s.z + 0.5);
    if (_has(site, StructureMark.boss) || game.player.position.distanceTo(chamber) >= kingWakesWithin) return;
    if (!game.world.isLoaded(IVec3.floor(chamber))) return;
    _mark(site, StructureMark.boss);
    _wake(game, 'mummy_king', chamber + Vector3(0.0, 0.05, -1.0), 2);
    game.notify('The Mummy King stirs!');
    game.playSound('thunder', volumeDb: -8.0, pitch: 1.6);
  }

  // The troll in the last room; the guard rooms' spawners.
  void _dungeon(VoxelGame game, PlacedStructure s, _Site site) {
    final plan = DungeonPlan.of(dungeonStructure, s, game.world.generator.rollOf(s));
    for (final spawner in plan.spawners) {
      _spawner(game, spawner);
    }
    final centre = plan.rooms.last.centre;
    final room = Vector3(centre.x + 0.5, centre.y.toDouble(), centre.z + 0.5);
    if (_has(site, StructureMark.boss) || game.player.position.distanceTo(room) >= trollWakesWithin) return;
    if (!game.world.isLoaded(centre)) return;
    _mark(site, StructureMark.boss);
    _wake(game, 'troll', room + Vector3(-2.0, 0.0, 2.0), 2);
    game.notify('A Cave Troll guards the treasure!');
  }

  // The mine's spawner, a few cells before its chest when it has one.
  void _mineSpawner(VoxelGame game, PlacedStructure s) {
    final spawner = MinePlan.of(mineStructure, s, game.world.generator.rollOf(s)).spawner;
    if (spawner != null) _spawner(game, spawner);
  }

  /// Brings one of [spawnerBrood] beside the spawner block at [cell], if it
  /// is one and the player is near.
  void _spawner(VoxelGame game, IVec3 cell) {
    if (cell.distanceTo(game.player.position) > spawnerReach) return;
    if (!game.world.isLoaded(cell) || game.world.blockNameAt(cell) != spawnerBlock) return;
    final centre = cell.centre;
    if (game.mobs.where((m) => !m.isDead && m.position.distanceTo(centre) < crowdWithin).length >= crowdMost) return;
    if (game.random.nextDouble() < spawnerSkip) return;
    final side = game.random.nextBool() ? 1.0 : -1.0;
    final at = Vector3(centre.x + side * (1.0 + game.random.nextDouble()), cell.y.toDouble(), centre.z);
    _wake(game, spawnerBrood[game.random.nextInt(spawnerBrood.length)], at, 1);
  }

  /// The spawner block's name.
  static const String spawnerBlock = 'spawner';

  // A ghost by a ruin at night.
  void _haunt(VoxelGame game, PlacedStructure s) {
    if (!game.isNight) return;
    final at = Vector3(s.x.toDouble(), s.y.toDouble(), s.z.toDouble());
    if (game.player.position.distanceTo(at) > hauntReach || game.random.nextDouble() > hauntChance) return;
    final near = game.mobs.where((m) => m.spec.id == 'ghost' && !m.isDead && m.position.distanceTo(at) < ghostsWithin);
    if (near.length >= ghostsMost) return;
    final x = s.x + game.random.nextInt(9) - 4, z = s.z + game.random.nextInt(9) - 4;
    if (!game.world.isLoaded(IVec3(x, s.y, z))) return;
    _wake(game, 'ghost', Vector3(x + 0.5, game.world.groundHeight(x, z).toDouble(), z + 0.5), 1);
  }

  // The fortress: told and its achievement, then its blazes, then its lord.
  void _fortress(VoxelGame game, PlacedStructure s, _Site site, double d) {
    if (d < foundWithin && _mark(site, StructureMark.told)) {
      game.notify('A fortress looms in the dark!');
      Achievements.of(game).unlock(game, 'underworld');
    }
    final plan = fortressAt(game, s);
    final here = game.player.position;
    final middle = plan.middle.centre;
    if (!_has(site, StructureMark.blazes) &&
        here.distanceTo(middle) < blazesWakeWithin &&
        game.world.isLoaded(plan.middle)) {
      _mark(site, StructureMark.blazes);
      for (var i = 0; i < 2; i++) {
        _wake(game, 'blaze', middle + Vector3(i * 2.0 - 1.0, 1.0, 0.0), 1);
      }
      game.notify('Blazes!');
    }
    final core = plan.core;
    if (!_has(site, StructureMark.boss) && core.distanceTo(here) < lordWakesWithin && game.world.isLoaded(core)) {
      _mark(site, StructureMark.boss);
      final lord = _wake(game, 'underworld_lord', Vector3(core.x + 2.0, core.y + 1.6, core.z + 0.5), 3);
      lord.data[coreKey] = [core.x, core.y, core.z];
      game.notify('The Underworld Lord rises!');
      game.playSound('thunder', volumeDb: -6.0, pitch: 1.2);
    }
  }

  /// A creature of [id] at [at], [above] levels over the player's (the old
  /// game's, whose levels counted from 1).
  static Mob _wake(VoxelGame game, String id, Vector3 at, int above) {
    final mob = game.spawnMob(id, at);
    mob.growTo(game.player.level + 1 + above);
    return mob;
  }

  /// The lord's death unseals his core.
  @override
  void onEvent(VoxelGame game, GameEvent event) {
    if (!game.authority) return;
    if (event case MobKilled(:final mob) when mob.spec.id == 'underworld_lord') {
      final c = mob.data[coreKey]! as List<Object?>;
      final core = IVec3(c[0]! as int, c[1]! as int, c[2]! as int);
      game.world.storeEdit(core, game.blocks.indexOf(openCore));
      game.notify('The fortress core is unsealed!');
    }
  }

  static _Site _siteOf(String dimension, PlacedStructure s) =>
      (dimension: dimension, name: s.name, x: s.x, y: s.y, z: s.z);

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {
    'sites': [
      for (final MapEntry(key: s, value: marks) in _done.entries)
        [s.dimension, s.name, s.x, s.y, s.z, for (final m in marks) m.name],
    ],
  };

  /// Puts back what was done where; throws for a mark it does not know.
  @override
  void restore(VoxelGame game, Object? saved) {
    final s = saved! as Map<String, Object?>;
    _done.clear();
    for (final row in (s['sites']! as List<Object?>).cast<List<Object?>>()) {
      final site = (
        dimension: row[0]! as String,
        name: row[1]! as String,
        x: row[2]! as int,
        y: row[3]! as int,
        z: row[4]! as int,
      );
      _done[site] = {for (final m in row.skip(5)) StructureMark.values.byName(m! as String)};
    }
  }
}

/// A structure's site in a dimension: what the save keys what was done by.
typedef _Site = ({String dimension, String name, int x, int y, int z});
