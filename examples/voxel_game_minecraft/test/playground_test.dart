import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game_minecraft/src/classes/class_table.dart';
import 'package:voxel_game_minecraft/src/playground/exhibit_builder.dart';
import 'package:voxel_game_minecraft/src/playground/playground.dart';
import 'package:voxel_game_minecraft/src/playground/playground_zone.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/spec/mob_table.dart';

/// The playground's pure pieces, which `exhibits_test.dart` sees built: the
/// zone grid on the plaza, where the arena's and the rails' parts stand, and
/// the lists the builder reads (gallery, library, kits, arena, boss plates,
/// lights).
void main() {
  final blocks = gameSpec.buildBlocks();
  final items = gameSpec.buildItems(blocks);
  final mobs = {for (final m in mobTable) m.id};

  test('nine zones tile the plaza exactly, the spawn is in the hub', () {
    const plaza = Playground.plaza;
    expect(Playground.zones.map((z) => z.id).toSet(), hasLength(9));
    for (var x = plaza.minX; x < plaza.maxX; x += 6) {
      for (var z = plaza.minZ; z < plaza.maxZ; z += 6) {
        expect(Playground.zones.where((zone) => zone.contains(x + 0.5, z + 0.5)), hasLength(1), reason: '($x, $z)');
      }
    }
    expect(Playground.zone('hub').contains(Playground.spawn.x, Playground.spawn.z), isTrue);
    expect(Playground.zones.any((zone) => zone.contains(plaza.maxX + 0.5, 8)), isFalse);
  });

  test("the arena's spawner, gold button and boss plates sit inside the arena", () {
    final arena = Playground.zone('arena');
    final cells = [
      ExhibitBuilder.arenaSpawnerCell(arena),
      ExhibitBuilder.arenaRefillCell(arena),
      for (var i = 0; i < ExhibitBuilder.bossPlates.length; i++) ExhibitBuilder.bossPlateCell(arena, i),
    ];
    for (final c in cells) {
      expect(arena.contains(c.x + 0.5, c.z + 0.5), isTrue, reason: '$c');
    }
  });

  test('the rail loop is closed, one step per cell, climbing at most one, inside its zone', () {
    final zone = Playground.zone('rails');
    final loop = ExhibitBuilder.railLoop(ExhibitBuilder.railStart(zone));
    expect(loop.toSet(), hasLength(loop.length));
    for (var i = 0; i < loop.length; i++) {
      final a = loop[i], b = loop[(i + 1) % loop.length];
      expect((a.x - b.x).abs() + (a.z - b.z).abs(), 1, reason: '$a -> $b');
      expect((a.y - b.y).abs(), lessThanOrEqualTo(1), reason: '$a -> $b');
      expect(zone.contains(a.x + 0.5, a.z + 0.5), isTrue, reason: '$a');
    }
    expect(loop.map((c) => c.y).reduce((a, b) => a > b ? a : b), Playground.floor + 2);
  });

  test('the gallery holds every placeable block once, no liquid, portal or spawner', () {
    final ids = ExhibitBuilder.galleryBlocks(blocks).map(blocks.idOf).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final left in ['air', 'water', 'water_flow', 'lava', 'lava_flow', 'portal', 'spawner']) {
      expect(ids, isNot(contains(left)));
    }
    expect(ids, contains('fortress_core'));
    expect(ids, hasLength(blocks.count - 7));
    // 13 pedestals a row, 3 apart, from 18 west of the centre: the last row inside the zone.
    expect((ids.length - 1) ~/ ExhibitBuilder.galleryColumns * 3 - 18, lessThan(PlaygroundZone.half - 4));
  });

  test("the library lists every item and its chests fit the hub's west side; every kit is real items", () {
    final library = ExhibitBuilder.libraryItems(items);
    expect(library.toSet(), {for (final t in items.all) t.id});
    expect(library, hasLength(items.all.length));
    expect(items[library.first].block, isNotNull, reason: 'the blocks come first');
    // A chest every 2 blocks from 6 north of the centre.
    final chests = (library.length / blocks[blocks.indexOf('chest')].storage!.slots).ceil();
    expect(-6 + (chests - 1) * 2, lessThan(PlaygroundZone.half));
    for (final cls in playerClasses.keys) {
      final kit = Playground.kitFor({'class': cls});
      expect(kit.length, lessThanOrEqualTo(36));
      expect(kit.first, playerClasses[cls]!.weapon);
      for (final id in kit) {
        expect(items.has(id), isTrue, reason: id);
      }
    }
  });

  test("the arena's creatures, its bosses and their plates, the pens and the lights are the game's", () {
    for (final id in ExhibitBuilder.arenaMobs) {
      expect(mobs, contains(id));
    }
    for (final (boss, marker) in ExhibitBuilder.bossPlates) {
      expect(mobs, contains(boss));
      expect(blocks.has(marker), isTrue, reason: marker);
    }
    for (final pen in ExhibitBuilder.pens) {
      expect(mobs, containsAll(pen.toSet()));
    }
    for (final id in ExhibitBuilder.lightSources) {
      expect(blocks[blocks.indexOf(id)].light, greaterThan(0), reason: id);
    }
  });
}
