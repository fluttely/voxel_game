import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/journal/achievements.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/structures/fortress.dart';
import 'package:voxel_game_minecraft/src/structures/structures.dart';

const _options = {'class': 'warrior'};

final VoxelGameSpec _spec = gameSpec.copyWith(player: gameSpec.playerWith(_options));

/// A warrior's game with no tutorial and no spawns of the world's own, as the
/// title starts one; from [save] when given.
Future<VoxelGame> _start({SavedWorld? save}) async {
  final game = await VoxelGame.startHeadless(_spec, options: _options, save: save);
  game.spawner.enabled = false;
  await _until(game, () => game.ready);
  return game;
}

/// Frames until [done], the workers given time to load the world.
Future<void> _until(VoxelGame game, bool Function() done, {void Function()? each}) async {
  for (var i = 0; i < 6000 && !done(); i++) {
    each?.call();
    game.frame(1 / 60);
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(done(), isTrue);
}

void _run(VoxelGame game, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.step(1 / 60);
  }
}

/// The structure named [name] nearest the player in the dimension streaming.
PlacedStructure _nearest(VoxelGame game, String name) {
  final p = game.player.position;
  final here = IVec3.floor(p);
  final cx = here.x >> 4, cz = here.z >> 4;
  final found = {
    for (var dx = -64; dx <= 64; dx += 4)
      for (var dz = -64; dz <= 64; dz += 4)
        for (final s in game.world.generator.structuresNear(cx + dx, cz + dz))
          if (s.name == name) s,
  }.toList()..sort((a, b) => _flat(a).distanceTo(p).compareTo(_flat(b).distanceTo(p)));
  return found.first;
}

Vector3 _flat(PlacedStructure s) => Vector3(s.x + 0.5, 0, s.z + 0.5);

/// Stands the player at [at], kept there until the world is loaded about it,
/// and lets the structures look.
Future<void> _standAt(VoxelGame game, Vector3 at) async {
  await _until(game, () => game.world.isLoaded(IVec3.floor(at)), each: () => game.player.placeAt(at));
  game.player.placeAt(at);
  _run(game, Structures.lookEvery + 0.1);
}

/// Stands the player on the ground [metres] east of [s]'s site.
Future<void> _standBy(VoxelGame game, PlacedStructure s, double metres) async {
  final x = s.x + metres, z = s.z.toDouble();
  final above = Vector3(x + 0.5, s.y + 20.0, z + 0.5);
  await _until(game, () => game.world.isLoaded(IVec3.floor(above)), each: () => game.player.placeAt(above));
  await _standAt(game, Vector3(x + 0.5, game.world.groundHeight(x.floor(), z.floor()).toDouble(), z + 0.5));
}

/// Where the player stands in the dungeon at [s]'s last room: over its chest,
/// found from below in the room's middle.
Future<Vector3> _lastRoomOf(VoxelGame game, PlacedStructure s) async {
  final column = IVec3(s.x + 12, s.y, s.z);
  await _until(game, () => game.world.isLoaded(column), each: () => game.player.placeAt(column.centre));
  for (var y = s.y - 13; y <= s.y; y++) {
    if (game.world.blockNameAt(IVec3(s.x + 12, y, s.z)) == 'chest') return Vector3(s.x + 10.5, y.toDouble(), s.z + 0.5);
  }
  throw StateError('no chest in the dungeon at $s');
}

Iterable<String> _told(VoxelGame game) => game.notices.feed.map((n) => n.text);

Iterable<Mob> _alive(VoxelGame game, String id) => game.mobs.where((m) => m.spec.id == id && !m.isDead);

void main() {
  test('the bosses are kept by the save, and a fortress chest holds its own loot', () {
    for (final id in ['mummy_king', 'underworld_lord']) {
      expect(gameSpec.mobs.firstWhere((m) => m.id == id).persistent, isTrue, reason: id);
    }
    expect(gameSpec.mobs.firstWhere((m) => m.id == 'troll').persistent, isFalse, reason: 'a cave spawn too');
    expect(gameSpec.structureLoot, contains('fortress'));
  });

  test('a structure within 48 m is found, and a ruin told within 24 m, once', () async {
    final game = await _start();
    final structures = Structures.of(game);
    final ruin = _nearest(game, 'ruins');
    await _standBy(game, ruin, 34.0);
    expect(structures.did('world', ruin, StructureMark.found), isTrue);
    expect(structures.foundIn('world'), contains(ruin));
    expect(structures.foundIn('underworld'), isEmpty);
    expect(_told(game), isNot(contains(Structures.minorStructureFound['ruins'])));

    await _standBy(game, ruin, 12.0);
    expect(structures.did('world', ruin, StructureMark.told), isTrue);
    _run(game, 3.0);
    expect(_told(game).where((t) => t == Structures.minorStructureFound['ruins']), hasLength(1));
    game.dispose();
  });

  test("the temple's mummy king wakes once, in its chamber, and the save keeps both", () async {
    final dir = Directory.systemTemp.createTempSync('structures');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final game = await _start();
    final temple = _nearest(game, 'temple');
    await _standBy(game, temple, 12.0);
    expect(_alive(game, 'mummy_king'), isEmpty, reason: 'it waits for the chamber');
    expect(_told(game), contains(Structures.minorStructureFound['temple']));

    await _standAt(game, Vector3(temple.x + 0.5, temple.y + 1.0, temple.z + 1.5));
    expect(_alive(game, 'mummy_king'), hasLength(1));
    final king = _alive(game, 'mummy_king').single;
    expect(king.position.distanceTo(Vector3(temple.x + 0.5, temple.y + 1.0, temple.z + 0.5)), lessThan(2.0));
    expect(king.level, game.player.level + 3);
    expect(_told(game), contains('The Mummy King stirs!'));
    _run(game, 3.0);
    expect(_alive(game, 'mummy_king'), hasLength(1), reason: 'once');

    saves.save(game, 'temple');
    game.dispose();
    final loaded = await _start(save: saves.read('temple'));
    expect(Structures.of(loaded).did('world', temple, StructureMark.boss), isTrue);
    expect(_alive(loaded, 'mummy_king'), hasLength(1), reason: 'kept by the save');
    await _standAt(loaded, Vector3(temple.x + 0.5, temple.y + 1.0, temple.z + 1.5));
    expect(_alive(loaded, 'mummy_king'), hasLength(1), reason: 'not woken again');
    loaded.dispose();
  });

  test("the dungeon's troll wakes in its last room, and its spawners bring creatures until broken", () async {
    final game = await _start();
    final dungeon = _nearest(game, 'dungeon');
    final room = await _lastRoomOf(game, dungeon);
    await _standAt(game, room);
    expect(_alive(game, 'troll'), hasLength(1));
    expect(_told(game), contains('A Cave Troll guards the treasure!'));

    _run(game, 20.0);
    final brood = game.mobs.where((m) => !m.isDead && Structures.spawnerBrood.contains(m.spec.id)).toList();
    expect(brood, isNotEmpty, reason: 'the middle room\'s spawner is within 13 m of the last room');
    for (final m in game.mobs.where((m) => m.spec.id != 'troll')) {
      m.kill(dropLoot: false);
    }
    final floor = room.y.floor() - 1;
    for (final x in [dungeon.x - 12, dungeon.x]) {
      final spawner = IVec3(x, floor + 1, dungeon.z + 2);
      expect(game.world.blockNameAt(spawner), Structures.spawnerBlock);
      game.world.setBlock(spawner, 0);
    }
    _run(game, 20.0);
    expect(game.mobs.where((m) => !m.isDead && Structures.spawnerBrood.contains(m.spec.id)), isEmpty);
    game.dispose();
  });

  test('a ruin is haunted at night, two ghosts at the most, and not by day', () async {
    final game = await _start();
    final ruin = _nearest(game, 'ruins');
    game.timeOfDay = 0.0;
    // In the ruin, so the ghosts that hunt the player stay by it.
    await _standBy(game, ruin, 1.0);
    _run(game, 15.0);
    final ghosts = _alive(game, 'ghost').length;
    expect(ghosts, inInclusiveRange(1, Structures.ghostsMost));

    for (final g in _alive(game, 'ghost')) {
      g.kill(dropLoot: false);
    }
    game.timeOfDay = 0.5;
    _run(game, 20.0);
    expect(_alive(game, 'ghost'), isEmpty);
    game.dispose();
  });

  test("the underworld's fortress: told, its blazes, its lord, and the core he seals", () async {
    final game = await _start();
    game.travel('underworld');
    await _until(game, () => game.travelState is! Arriving);
    final fort = _nearest(game, 'fortress');
    final plan = Structures.fortressAt(game, fort);
    final structures = Structures.of(game);

    await _standAt(game, plan.middle.centre);
    expect(game.world.blockNameAt(IVec3(plan.start, plan.floor, plan.z)), 'nether_brick');
    expect(game.world.blockNameAt(plan.middle), 'air');
    expect(_told(game), contains('A fortress looms in the dark!'));
    expect(Achievements.of(game).has('underworld'), isTrue);
    expect(_alive(game, 'blaze'), hasLength(2));
    expect(_told(game), contains('Blazes!'));
    expect(_alive(game, 'underworld_lord'), isEmpty, reason: 'the core is out of reach');
    expect(structures.foundIn('underworld'), contains(fort));

    final chest = IVec3(plan.start + plan.length ~/ 3, plan.floor + 1, plan.z + 7);
    await _standAt(game, chest.centre + Vector3(0, 0, -2));
    expect(game.world.blockNameAt(chest), 'chest');
    expect(game.structureAt(chest)?.name, 'fortress');

    final core = plan.core;
    await _standAt(game, Vector3(core.x - 2.5, core.y + 1.0, core.z + 0.5));
    expect(game.world.blockNameAt(core), sealedCore);
    expect(game.blocks[game.blocks.indexOf(sealedCore)].hardness, lessThan(0), reason: 'nothing breaks it');
    final lord = _alive(game, 'underworld_lord').single;
    expect(lord.data[Structures.coreKey], [core.x, core.y, core.z]);
    expect(_told(game), contains('The Underworld Lord rises!'));
    _run(game, 2.0);
    expect(_alive(game, 'underworld_lord'), hasLength(1), reason: 'once');

    lord.kill();
    _run(game, 0.1);
    expect(game.world.blockNameAt(core), openCore);
    expect(_told(game), contains('The fortress core is unsealed!'));
    game.dispose();
  });
}
