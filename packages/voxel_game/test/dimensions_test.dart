import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart' show ChunkPos, EditDeltaCodec;
import 'package:voxel_game/voxel_game.dart';

const _portal = PortalSpec(frame: 'obsidian', portal: 'portal', lighter: 'flint', to: 'nether');

const _spec = VoxelGameSpec(
  blocks: [
    BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
    BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType('planks', color: 0xB08850, hardness: 1.0, tool: 'axe'),
    BlockType('obsidian', color: 0x1A1028, hardness: 10, tool: 'pickaxe'),
    BlockType('portal', color: 0x8A2BE2, solid: false, alpha: 0.6, light: 11, hardness: -1, drop: ''),
    BlockType('netherrack', color: 0x6E2A2A, hardness: 0.4, tool: 'pickaxe'),
    BlockType('bedrock', color: 0x303030, hardness: -1),
    BlockType('chest', color: 0x8A5A2A, hardness: 2.0, tool: 'axe', storage: Storage()),
    BlockType.liquid('water', color: 0x3366CC),
    BlockType.liquid('lava', color: 0xE05A10, light: 15),
  ],
  items: [ItemType('flint', color: 0x404040, stack: 1, durability: 10)],
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  dimensions: {
    'nether': WorldGenSpec(
      terrain: TerrainRecipe.flat(40),
      seaLevel: 5,
      stone: 'netherrack',
      caves: CaveSpec.none,
      biomes: [Biome('wastes', top: 'netherrack', precipitation: Precipitation.none)],
    ),
    'deep': WorldGenSpec(
      cavern: CavernSpec(),
      stone: 'netherrack',
      water: 'lava',
      seaLevel: 28,
      bedrock: 'bedrock',
      caves: CaveSpec.none,
      biomes: [Biome('caverns', top: 'netherrack', precipitation: Precipitation.none)],
    ),
    'sea': WorldGenSpec(
      terrain: TerrainRecipe.flat(10),
      seaLevel: 30,
      caves: CaveSpec.none,
      biomes: [Biome('deeps', top: 'dirt')],
    ),
  },
  portals: [_portal],
  mobs: [MobSpec('dummy', hp: 10, brain: [])],
  seed: 7,
  sky: SkySpec.alwaysDay,
);

Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

Future<VoxelGame> _start({SavedWorld? save, VoxelGameSpec spec = _spec}) async {
  final game = await VoxelGame.startHeadless(spec, save: save);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
  return game;
}

/// Runs until the player has arrived (or ten seconds have gone).
Future<void> _arrive(VoxelGame game) async {
  for (var i = 0; i < 600 && game.travelState is Arriving; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.travelState, isNot(isA<Arriving>()));
  expect(game.ready, isTrue);
}

/// An obsidian frame on the ground ahead of the player, across x, its hollow
/// two wide and three tall, unlit: returns the hollow's low corner.
IVec3 _frame(VoxelGame game, {IVec3 offset = const IVec3(3, 0, -4)}) {
  final c = IVec3.floor(game.player.position) + offset;
  for (var dx = -1; dx <= 2; dx++) {
    for (var dy = -1; dy <= 3; dy++) {
      final inside = dx >= 0 && dx <= 1 && dy >= 0 && dy <= 2;
      game.world.setBlockNamed(c + IVec3(dx, dy, 0), inside ? 'air' : 'obsidian');
    }
  }
  return c;
}

int _count(VoxelGame game, String block, IVec3 around, int r) {
  final id = game.blocks.indexOf(block);
  var n = 0;
  for (var y = -r; y <= r; y++) {
    for (var z = -r; z <= r; z++) {
      for (var x = -r; x <= r; x++) {
        if (game.world.getBlock(around + IVec3(x, y, z)) == id) n++;
      }
    }
  }
  return n;
}

void main() {
  group('the spec', () {
    test('numbers the dimensions after the main world', () {
      expect(_spec.dimensionIds, ['world', 'nether', 'deep', 'sea']);
      expect(_spec.dimensionWorlds.first, same(_spec.world));
      expect(_portal.otherEnd('world'), 'nether');
      expect(_portal.otherEnd('nether'), 'world');
      expect(_portal.otherEnd('deep'), isNull);
    });

    test('throws for a dimension named world and for a portal that cannot be', () async {
      Future<void> refused(VoxelGameSpec spec) =>
          expectLater(VoxelGame.startHeadless(spec), throwsA(isA<ArgumentError>()));
      await refused(_spec.copyWith(dimensions: {'world': _spec.world}));
      await refused(
        _spec.copyWith(
          portals: [const PortalSpec(frame: 'obsidian', portal: 'portal', lighter: 'flint', to: 'end')],
        ),
      );
      await refused(
        _spec.copyWith(
          portals: [const PortalSpec(frame: 'obsidian', portal: 'portal', lighter: 'flint', to: 'world')],
        ),
      );
      await refused(
        _spec.copyWith(
          portals: [const PortalSpec(frame: 'obsidian', portal: 'stone', lighter: 'flint', to: 'nether')],
        ),
      );
      await refused(
        _spec.copyWith(
          portals: [const PortalSpec(frame: 'glass', portal: 'portal', lighter: 'flint', to: 'nether')],
        ),
      );
      await refused(
        _spec.copyWith(
          portals: [const PortalSpec(frame: 'obsidian', portal: 'portal', lighter: 'torch', to: 'nether')],
        ),
      );
      await refused(
        _spec.copyWith(
          portals: [
            _portal,
            const PortalSpec(frame: 'planks', portal: 'portal', lighter: 'flint', to: 'deep'),
          ],
        ),
      );
    });
  });

  group('travel', () {
    test('takes the player to another dimension, standing at its column, and leaves the creatures behind', () async {
      final game = await _start();
      final at = game.player.position.clone();
      game.spawnMob('dummy', at + Vector3(0, 0, -5));
      await _run(game, 0.1);
      expect(game.mobs, hasLength(1));
      game.travel('nether');
      expect(game.travelState, isA<Arriving>());
      expect(game.ready, isFalse, reason: 'off the ground until the world is loaded');
      expect(game.mobs, isEmpty);
      expect(game.dimension, 'nether');
      expect(game.world.dimension, 1);
      await _arrive(game);
      expect(game.player.position.x, at.x);
      expect(game.player.position.z, at.z);
      expect(game.player.position.y, closeTo(40.0, 0.01), reason: 'on the nether\'s ground');
      expect(game.world.blockNameAt(IVec3.floor(game.player.position) + IVec3.down), 'netherrack');
      await _run(game, 1.0);
      expect(game.player.position.y, closeTo(40.0, 0.01), reason: 'it stands, it does not fall');
      expect(() => game.travel('nether'), throwsArgumentError);
      expect(() => game.travel('moon'), throwsArgumentError);
    });

    test('keeps each dimension\'s edits for when it comes back', () async {
      final game = await _start();
      final cell = IVec3.floor(game.player.position) + const IVec3(2, 0, 0);
      game.world.setBlockNamed(cell, 'planks');
      game.travel('nether');
      await _arrive(game);
      final there = cell + const IVec3(0, 20, 0);
      expect(game.world.blockNameAt(cell), 'netherrack');
      game.world.setBlockNamed(there, 'stone');
      expect(game.world.editCountIn(0), 1);
      expect(game.world.editCountIn(1), 1);
      game.travel('world');
      await _arrive(game);
      expect(game.world.blockNameAt(cell), 'planks');
      expect(game.world.blockNameAt(there), 'air');
      // An edit of a dimension not streaming waits for it.
      game.world.storeEditIn(1, there + IVec3.up, game.blocks.indexOf('planks'));
      game.travel('nether');
      await _arrive(game);
      expect(game.world.blockNameAt(there), 'stone');
      expect(game.world.blockNameAt(there + IVec3.up), 'planks');
    });

    test('arrives in a cavern on a floor above its sea, and carves a pocket where there is no floor', () async {
      final game = await _start();
      game.travel('deep');
      await _arrive(game);
      final feet = IVec3.floor(game.player.position);
      expect(feet.y, greaterThan(28));
      expect(game.world.blocks[game.world.getBlock(feet + IVec3.down)].solid, isTrue);
      expect(game.world.blockNameAt(feet + IVec3.down), isNot('lava'));
      expect(game.world.blockNameAt(feet), 'air');
      expect(game.world.blockNameAt(feet + IVec3.up), 'air');
      game.travel('sea');
      await _arrive(game);
      final wet = IVec3.floor(game.player.position);
      expect(wet.y, 31, reason: 'over the sea, on the stone the arrival put there');
      expect(game.world.blockNameAt(wet + IVec3.down), 'stone');
    });

    test('a death elsewhere stands the player up at its spawn, in the main world', () async {
      final game = await _start();
      final spawn = game.player.spawnPoint.clone();
      game.travel('nether');
      await _arrive(game);
      game.player.kill();
      await _run(game, game.spec.player.respawnDelay + 0.1);
      game.respawn();
      expect(game.dimension, 'world');
      await _arrive(game);
      expect(game.player.position.distanceTo(spawn), lessThan(0.02));
      expect(game.player.isDead, isFalse);
    });

    test('a store\'s screen shuts, and each dimension keeps its own stores', () async {
      final game = await _start();
      final cell = IVec3.floor(game.player.position) + const IVec3(2, 0, 0);
      game.world.setBlockNamed(cell, 'chest');
      game.blockRules.storeAt(cell).add('planks', 3);
      game.openScreen(StorageScreen(cell));
      game.travel('nether');
      expect(game.screen.value, isNull);
      await _arrive(game);
      expect(game.blockRules.stores, isEmpty);
      expect(game.blockRules.storesIn(0)[cell]!.countOf('planks'), 3);
    });
  });

  group('portals', () {
    test('a closed frame lights, in either plane; an open one does not', () async {
      final game = await _start();
      final corner = _frame(game);
      expect(game.portals.lights('flint'), isTrue);
      expect(game.portals.lights('planks'), isFalse);
      expect(game.portals.lightWith('flint', corner + const IVec3(1, 2, 0)), isTrue);
      expect(_count(game, 'portal', corner, 4), 6);
      expect(game.portals.at(corner), same(_portal));
      expect(game.portals.nearest(_portal, corner + const IVec3(5, 0, 0), 8), corner + const IVec3(1, 0, 0));

      // Across z, one side missing: no; the side put back: yes.
      final c = IVec3.floor(game.player.position) + const IVec3(-4, 0, 0);
      for (var dz = -1; dz <= 2; dz++) {
        for (var dy = -1; dy <= 3; dy++) {
          final inside = dz >= 0 && dz <= 1 && dy >= 0 && dy <= 2;
          if (!inside) game.world.setBlockNamed(c + IVec3(0, dy, dz), 'obsidian');
        }
      }
      game.world.setBlockNamed(c + const IVec3(0, 1, 2), 'air');
      expect(game.portals.lightWith('flint', c), isFalse);
      expect(_count(game, 'portal', c, 3), 0);
      game.world.setBlockNamed(c + const IVec3(0, 1, 2), 'obsidian');
      expect(game.portals.lightWith('flint', c + const IVec3(0, 1, 1)), isTrue);
      expect(_count(game, 'portal', c, 3), 6);
    });

    test('the lighter in hand, used on the hollow, lights it and wears', () async {
      final game = await _start();
      game.playWithoutCapture = true;
      final feet = IVec3.floor(game.player.position);
      final corner = _frame(game, offset: const IVec3(0, 0, -3));
      game.player
        ..position = Vector3(feet.x + 0.5, feet.y.toDouble(), feet.z + 0.5)
        ..yaw = 0.0
        ..pitch = -0.495;
      game.player.inventory.setSlot(0, ItemStack('flint', 1));
      game.player.selectedSlot = 0;
      game.input.tap(VoxelAction.use);
      await _run(game, 0.05);
      expect(_count(game, 'portal', corner, 4), 6);
      expect(game.player.inventory.slots[0]!.dur, 9, reason: 'one of its ten uses spent');
    });

    test('standing in one takes the player through, a return portal is built, and it leads back', () async {
      final game = await _start();
      final corner = _frame(game);
      game.portals.lightWith('flint', corner);
      game.player.position = Vector3(corner.x + 0.5, corner.y.toDouble(), corner.z + 0.5);
      await _run(game, 0.5);
      expect(game.travelState, isA<Charging>());
      expect((game.travelState as Charging).progress, closeTo(0.25, 0.05));
      await _run(game, 1.6);
      expect(game.dimension, 'nether');
      await _arrive(game);
      final feet = IVec3.floor(game.player.position);
      expect((feet.x, feet.z), (corner.x, corner.z), reason: 'the same column');
      final back = game.portals.nearest(_portal, feet, 4);
      expect(back, isNotNull, reason: 'a way back is built');
      expect(_count(game, 'portal', feet, 4), 6);
      expect(game.portals.at(feet), isNull, reason: 'it arrives in front of the portal, not in it');
      await _run(game, 0.1);
      expect(game.travelState, isA<Staying>());

      // In and through again: the main world's portal is near, so no second one is built.
      game.player.position = Vector3(back!.x + 0.5, back.y.toDouble(), back.z + 0.5);
      await _run(game, 2.2);
      expect(game.dimension, 'world');
      await _arrive(game);
      expect(_count(game, 'portal', corner, 8), 6);
    });

    test('a portal of another dimension\'s pair does not charge', () async {
      final game = await _start();
      game.travel('deep');
      await _arrive(game);
      final feet = IVec3.floor(game.player.position);
      game.world.setBlockNamed(feet, 'portal');
      await _run(game, 3.0);
      expect(game.dimension, 'deep');
      expect(game.travelState, isA<Staying>());
    });
  });

  group('the save', () {
    (WorldSaves, Directory) newSaves() {
      final dir = Directory.systemTemp.createTempSync('voxel_dimensions');
      addTearDown(() => dir.deleteSync(recursive: true));
      return (WorldSaves(dir), dir);
    }

    test('keeps the dimension the player is in, and every dimension\'s edits, crops and stores', () async {
      final (saves, _) = newSaves();
      final game = await _start();
      final cell = IVec3.floor(game.player.position) + const IVec3(2, 0, 0);
      game.world.setBlockNamed(cell, 'planks');
      game.world.setBlockNamed(cell + const IVec3(0, 0, 2), 'chest');
      game.blockRules.storeAt(cell + const IVec3(0, 0, 2)).add('flint', 1);
      game.travel('nether');
      await _arrive(game);
      final there = cell + const IVec3(0, 20, 0);
      game.world.setBlockNamed(there, 'stone');
      final at = game.player.position.clone();
      saves.save(game, 'two');
      final json = jsonDecode(File('${saves.directory.path}/two/game.json').readAsStringSync()) as Map<String, Object?>;
      expect(json['version'], WorldSaves.stateVersion);
      expect(json['dimensions'], ['world', 'nether', 'deep', 'sea']);
      expect((json['player']! as Map<String, Object?>)['dimension'], 'nether');

      final loaded = await _start(save: saves.read('two'));
      expect(loaded.dimension, 'nether');
      expect(loaded.player.position, at);
      expect(loaded.world.blockNameAt(there), 'stone');
      expect(loaded.blockRules.storesIn(0)[cell + const IVec3(0, 0, 2)]!.countOf('flint'), 1);
      loaded.travel('world');
      await _arrive(loaded);
      expect(loaded.world.blockNameAt(cell), 'planks');
    });

    test('a version 4 save, of the main world alone, still loads', () async {
      final (saves, dir) = newSaves();
      final game = await _start();
      final cell = IVec3.floor(game.player.position) + const IVec3(2, 0, 0);
      game.world.setBlockNamed(cell, 'planks');
      final store = cell + const IVec3(0, 0, 2);
      game.world.setBlockNamed(store, 'chest');
      game.blockRules.storeAt(store).add('flint', 1);
      saves.save(game, 'old');
      // Rewritten as the kit wrote it before dimensions.
      final file = File('${dir.path}/old/game.json');
      final s = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      s['version'] = 4;
      s.remove('dimensions');
      (s['player']! as Map<String, Object?>).remove('dimension');
      s['growing'] = (s['growing']! as Map<String, Object?>)['world'];
      s['stores'] = (s['stores']! as Map<String, Object?>)['world'];
      file.writeAsStringSync(jsonEncode(s));
      const v1 = EditDeltaCodec(magic: 0x314B5856, version: 1, dimensions: 1);
      File('${dir.path}/old/edits.bin').writeAsBytesSync(v1.encode(7, {0: game.world.edits[0]!}));

      final loaded = await _start(save: saves.read('old'));
      expect(loaded.dimension, 'world');
      expect(loaded.world.blockNameAt(cell), 'planks');
      expect(loaded.blockRules.stores[store]!.countOf('flint'), 1);
    });

    test('a save of a dimension the game no longer declares throws', () {
      const saved = SavedWorld(7, {}, {}, dimensions: ['world', 'end']);
      expect(() => saved.editsFor(_spec.dimensionIds), throwsStateError);
      expect(
        const SavedWorld(
          7,
          {1: <ChunkPos, Map<int, int>>{}},
          {},
          dimensions: ['world', 'sea'],
        ).editsFor(_spec.dimensionIds).keys,
        [0, 3],
      );
    });
  });

  test('over the network: edits carry their dimension, players are seen only in theirs, and so are the mobs', () async {
    final host = await _start();
    final session = await host.host(port: 0);
    final client = await VoxelGame.joinGame(_spec, '127.0.0.1', port: session.net.port, headless: true);
    client.spawner.enabled = false;
    Future<void> both(double seconds) async {
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        host.frame(1 / 60);
        client.frame(1 / 60);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    await both(1.0);
    expect(client.ready, isTrue);
    host.spawnMob('dummy', host.player.position + Vector3(0, 0, -6));
    await both(0.3);
    expect(client.mobs, hasLength(1));
    expect(host.playersHere, hasLength(1));

    client.travel('nether');
    for (var i = 0; i < 600 && client.travelState is Arriving; i++) {
      await both(1 / 60);
    }
    await both(0.5);
    expect(client.mobs, isEmpty, reason: 'the host\'s mobs live in the main world');
    expect(host.remotePlayers.single.dimension, 1);
    expect(host.playersHere, isEmpty, reason: 'its mobs do not hunt a player in another dimension');
    expect(host.allTargets, hasLength(2), reason: 'the host and its mob');
    expect(client.playersHere, isEmpty);

    final byClient = IVec3.floor(client.player.position) + const IVec3(2, 0, 0);
    client.world.setBlockNamed(byClient, 'planks');
    final byHost = IVec3.floor(host.player.position) + const IVec3(-2, 0, 0);
    host.world.setBlockNamed(byHost, 'stone');
    await both(0.5);
    expect(host.world.editCountIn(1), 1, reason: 'kept for the nether');
    expect(host.world.blockNameAt(byClient), isNot('planks'), reason: 'not written into the main world');
    expect(
      client.world.editCountIn(0),
      greaterThanOrEqualTo(1),
      reason: 'the host\'s edit waits for the client\'s return',
    );
    client.travel('world');
    for (var i = 0; i < 600 && client.travelState is Arriving; i++) {
      await both(1 / 60);
    }
    await both(0.5);
    expect(client.world.blockNameAt(byHost), 'stone');
    expect(client.mobs, hasLength(1), reason: 'back with the host\'s mobs');
    expect(host.playersHere, hasLength(1));
    host.dispose();
    client.dispose();
  });
}
