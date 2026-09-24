import 'dart:convert';
import 'dart:io';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/core/items.dart';
import 'package:voxel_game_minecraft/src/game/game_state.dart';
import 'package:voxel_game_minecraft/src/game/playground.dart';
import 'package:voxel_game_minecraft/src/game/rails.dart';
import 'package:voxel_game_minecraft/src/game/worlds.dart';
import 'package:voxel_game_minecraft/src/player/player.dart';
import 'package:voxel_game_minecraft/src/world/terrain_generator.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_engine/core.dart';

/// Stage 33's pure pieces (`--playground` covers the built exhibits in the
/// app): the flat plaza in the generator, the zone grid, the lists the
/// builders read (gallery, library, kit, arena, boss plates), the rail loop's
/// shape, and the playground slot in `Worlds`.
void main() {
  group('generator plaza', () {
    final flat = TerrainGenerator(ids: Blocks.generatorIds(), seed: Worlds.playgroundSeed, playground: true);
    final wild = TerrainGenerator(ids: Blocks.generatorIds(), seed: Worlds.playgroundSeed);

    test('the plaza is grass at the floor, eased back to the natural height outside', () {
      for (final (x, z) in const [(8, 8), (-64, -64), (79, 79), (-64, 79), (40, -30)]) {
        expect(flat.surfaceHeight(x, z), TerrainGenerator.plazaFloor, reason: '($x, $z)');
        expect(flat.biomeAt(x, z), TerrainGenerator.biomePlains);
      }
      const far = 80 + TerrainGenerator.plazaBlend + 5;
      expect(flat.surfaceHeight(far, 8), wild.surfaceHeight(far, 8));
      expect(TerrainGenerator.plazaDistance(80, 8), 1);
      expect(TerrainGenerator.plazaDistance(-65, -70), 6);
    });

    test('a plaza chunk is stone, dirt and one grass layer with nothing above it', () {
      final blocks = flat.generateIn(0, 0, 0);
      final grass = Blocks.indexOf('grass');
      for (var i = 0; i < 16; i++) {
        final x = (i * 7) % 16, z = (i * 5) % 16;
        expect(blocks[ChunkSize.index(x, TerrainGenerator.plazaFloor - 1, z)], grass);
        for (var y = TerrainGenerator.plazaFloor; y < ChunkSize.sizeY; y++) {
          expect(blocks[ChunkSize.index(x, y, z)], Blocks.air, reason: '($x, $y, $z)');
        }
      }
    });

    test('no structure stands within 48 blocks of the plaza', () {
      for (var cz = -8; cz <= 8; cz++) {
        for (var cx = -8; cx <= 8; cx++) {
          for (final s in flat.structuresNear(cx, cz)) {
            expect(TerrainGenerator.inPlaza(s.x, s.z, 48), isFalse, reason: '$s');
          }
        }
      }
    });

    test('the seed alone is not the plaza: a world built before the host\'s hello takes both, in its dimension', () async {
      // A client that joined a playground with the seed only stood in the sea
      // where the host stood on the plaza (the client's HUD read Ocean there).
      final w = VoxelWorld(seedValue: Worlds.playgroundSeed, loadRadius: 1);
      addTearDown(w.dispose);
      expect([w.playground, w.biomeAt(-29, -33)], [false, TerrainGenerator.biomeOcean]);
      w.switchDimension(VoxelWorld.dimUnderworld);
      await w.setWorldShape(Worlds.playgroundSeed, playground: true);
      expect([w.seedValue, w.playground, w.generator.dimension], [Worlds.playgroundSeed, true, VoxelWorld.dimUnderworld]);
      w.switchDimension(VoxelWorld.dimOverworld);
      expect([w.surfaceHeight(-29, -33), w.biomeAt(-29, -33)], [TerrainGenerator.plazaFloor, TerrainGenerator.biomePlains]);
    });
  });

  group('layout', () {
    test('nine zones tile the plaza exactly, the spawn is in the hub', () {
      expect(Playground.zones.length, 9);
      expect(Playground.zones.map((z) => z.id).toSet().length, 9);
      for (var x = TerrainGenerator.plazaMin; x < TerrainGenerator.plazaMax; x += 6) {
        for (var z = TerrainGenerator.plazaMin; z < TerrainGenerator.plazaMax; z += 6) {
          expect(Playground.zones.where((zone) => zone.contains(x + 0.5, z + 0.5)).length, 1, reason: '($x, $z)');
        }
      }
      expect(Playground.zone('hub').contains(Playground.spawn.x, Playground.spawn.z), isTrue);
      expect(Playground.zones.any((zone) => zone.contains(TerrainGenerator.plazaMax + 0.5, 8)), isFalse);
    });

    test('the arena plates and buttons sit inside the arena zone', () {
      final arena = Playground.zone('arena');
      final cells = [
        Playground.arenaSpawnerCell(arena),
        Playground.arenaRefillCell(arena),
        for (var i = 0; i < Playground.bossPlates.length; i++) Playground.bossPlateCell(arena, i),
      ];
      for (final c in cells) {
        expect(arena.contains(c.x + 0.5, c.z + 0.5), isTrue, reason: '$c');
      }
    });

    test('the rail loop is closed, one step per cell, climbing at most one', () {
      final loop = Playground.railLoop(0, 64, 0);
      expect(loop.toSet().length, loop.length);
      for (var i = 0; i < loop.length; i++) {
        final a = loop[i], b = loop[(i + 1) % loop.length];
        expect((a.x - b.x).abs() + (a.z - b.z).abs(), 1, reason: '$a -> $b');
        expect((a.y - b.y).abs(), lessThanOrEqualTo(1), reason: '$a -> $b');
      }
      expect(loop.map((c) => c.y).reduce((a, b) => a > b ? a : b), 66);
      expect(Rails.e, const IVec3(1, 0, 0));
    });
  });

  group('lists', () {
    test('the gallery holds every placeable block once, no liquid, portal or spawner', () {
      final ids = Playground.galleryBlocks().map(Blocks.idOf).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, isNot(contains('water')));
      expect(ids, isNot(contains('lava_flow')));
      expect(ids, isNot(contains('portal')));
      expect(ids, isNot(contains('spawner')));
      expect(ids, contains('fortress_core'));
      expect(ids.length, Blocks.count - 7); // air, four liquids, portal, spawner
      // 13 columns, 3 apart, starting 18 west of the centre: inside the zone.
      expect((ids.length - 1) ~/ Playground.galleryColumns * 3 - 18, lessThan(Playground.half - 4));
    });

    test('the library lists every item and fits its chests, the kit is real items', () {
      final lib = Playground.libraryItems();
      expect(lib.toSet(), Items.defs.keys.toSet());
      expect(Items.kind(lib.first), ItemKind.block);
      expect((lib.length / 36).ceil(), lessThanOrEqualTo(8));
      for (final cls in Player.classes.keys) {
        final kit = Playground.kitItems(cls);
        expect(kit.length, lessThanOrEqualTo(36));
        expect(kit.first, Player.classes[cls]!.weapon);
        for (final id in kit) {
          expect(Items.has(id), isTrue, reason: id);
        }
      }
    });

    test('arena creatures, bosses, their marker blocks and the light sources exist', () {
      for (final (species, affix) in Playground.arenaMobs) {
        expect(species, isNotEmpty);
        expect(affix == '' || const ['Giant', 'Venomous', 'Burning'].contains(affix), isTrue);
      }
      for (final (species, marker) in Playground.bossPlates) {
        expect(Blocks.has(marker), isTrue, reason: marker);
        expect(species, isNotEmpty);
      }
      for (final id in Playground.lightSources) {
        expect(Blocks.lightOf(Blocks.indexOf(id)), greaterThan(0), reason: id);
      }
    });
  });

  group('Worlds', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('stage33_worlds');
      Worlds.root = '${tmp.path}/worlds';
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('a playground slot is creative on the fixed seed, typed, and every one is new', () {
      final a = Worlds.createPlayground('mage', now: 7);
      final b = Worlds.createPlayground('rogue');
      expect([a, b], ['playground', 'playground_2']);
      final meta = jsonDecode(File('${Worlds.root}/$a/world.json').readAsStringSync()) as Map<String, dynamic>;
      expect(meta, {'name': 'Playground', 'seed': 42, 'mode': 'creative', 'class': 'mage', 'created': 7, 'type': 'playground'});
      final e = Worlds.entry(a)!;
      expect([e.playground, e.creative, Worlds.modeLabel(e)], [true, true, 'Playground']);
      Worlds.start(a);
      expect([GameState.instance.playground, GameState.instance.creative, GameState.instance.seedValue], [true, true, 42]);
      Worlds.start(Worlds.create('Plain', '1', 'survival', 'warrior'));
      expect(GameState.instance.playground, isFalse);
    });

    test('the flag rides the stats block of the save', () {
      final gs = GameState.instance;
      gs.resetStats();
      gs.playground = true;
      final json = jsonDecode(jsonEncode(gs.toJson())) as Map<String, dynamic>;
      expect(json['playground'], true);
      gs.resetStats();
      expect(gs.playground, isFalse);
      gs.fromJson(json);
      expect(gs.playground, isTrue);
      gs.resetStats();
    });
  });
}
