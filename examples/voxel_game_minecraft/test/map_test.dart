import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:voxel_engine/core.dart' show ChunkStreamer;
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/map/map_mark.dart';
import 'package:voxel_game_minecraft/src/map/map_painter.dart';
import 'package:voxel_game_minecraft/src/map/map_picture.dart';
import 'package:voxel_game_minecraft/src/map/map_screen.dart';
import 'package:voxel_game_minecraft/src/map/minimap.dart';
import 'package:voxel_game_minecraft/src/map/world_map.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/structures/structures.dart';
import 'package:voxel_game_minecraft/src/ui/game_hud.dart';
import 'package:voxel_game_minecraft/src/waypoints/waypoints.dart';

const _options = {'class': 'warrior', 'tutorial': 'off'};

final VoxelGameSpec _spec = gameSpec.copyWith(player: gameSpec.playerWith(_options));

/// A warrior's game with no tutorial and no spawns of the world's own, as the
/// title starts one; from [save] when given.
Future<VoxelGame> _start({SavedWorld? save}) async {
  final game = await VoxelGame.startHeadless(_spec, options: _options, save: save);
  game.spawner.enabled = false;
  await _until(game, () => game.ready);
  _run(game, 0.1);
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

/// Stands the player on the ground at column ([x], [z]), kept there until
/// the world is loaded about it, and lets the map and the structures look.
Future<void> _standOn(VoxelGame game, double x, double z) async {
  final above = Vector3(x, 120.0, z);
  await _until(game, () => game.world.isLoaded(IVec3.floor(above)), each: () => game.player.placeAt(above));
  game.player.placeAt(Vector3(x, game.world.groundHeight(x.floor(), z.floor()).toDouble(), z));
  _run(game, WorldMap.lookEvery + 0.1);
}

/// The structure named [name] nearest the player.
PlacedStructure _nearest(VoxelGame game, String name) {
  final p = game.player.position;
  final here = ChunkStreamer.chunkOf(IVec3.floor(p));
  double far(PlacedStructure s) => Vector3(s.x + 0.5, p.y, s.z + 0.5).distanceTo(p);
  final found = {
    for (var dx = -64; dx <= 64; dx += 4)
      for (var dz = -64; dz <= 64; dz += 4)
        for (final s in game.world.generator.structuresNear(here.x + dx, here.z + dz))
          if (s.name == name) s,
  }.toList()..sort((a, b) => far(a).compareTo(far(b)));
  return found.first;
}

/// One press of the map action, and the step that reads it.
void _press(VoxelGame game) {
  game.actions.tap(WorldMap.action);
  game.step(1 / 60);
}

void main() {
  test('every structure the worlds place is marked, and creatures are dotted by kind', () {
    final placed = {
      for (final w in [gameSpec.world, ...gameSpec.dimensions.values])
        for (final s in w.structures) s.name,
    };
    expect(MapPainter.structures.keys.toSet(), placed);
    MobSpec mob(String id) => gameSpec.mobs.firstWhere((m) => m.id == id);
    expect([
      for (final id in ['zombie', 'blaze', 'bat']) MapPainter.hostile(mob(id)),
    ], everyElement(isTrue));
    expect([
      for (final id in ['cow', 'wolf', 'bear', 'villager']) MapPainter.hostile(mob(id)),
    ], everyElement(isFalse));
  });

  test('the chunks the player stands in are explored, by dimension, and come back with the save', () async {
    final dir = Directory.systemTemp.createTempSync('map');
    addTearDown(() => dir.deleteSync(recursive: true));
    final game = await _start();
    final map = WorldMap.of(game);
    final start = game.player.position.clone();
    await _standOn(game, start.x + 40.0, start.z);
    final here = ChunkStreamer.chunkOf(IVec3.floor(game.player.position));
    final there = ChunkStreamer.chunkOf(IVec3.floor(start));
    expect(map.exploredIn('world'), containsAll([here, there]));
    expect(map.exploredIn('underworld'), isEmpty);

    final saves = WorldSaves(dir);
    saves.save(game, 'map');
    final explored = map.exploredIn('world');
    game.dispose();
    final loaded = await _start(save: saves.read('map'));
    expect(WorldMap.of(loaded).exploredIn('world'), containsAll(explored));
    loaded.dispose();
  });

  test('the map action shows the minimap, then the whole map in its place, then neither', () async {
    final game = await _start();
    final map = WorldMap.of(game);
    expect(map.minimap, isFalse);
    _press(game);
    expect(map.minimap, isTrue);
    expect(game.screen.value, isNull);
    _press(game);
    expect(map.minimap, isFalse);
    expect(game.screen.value, const DeclaredScreen(WorldMap.screen));
    _press(game);
    expect(game.screen.value, isNull);
    expect(map.minimap, isFalse);

    game.openScreen(const BagScreen());
    _press(game);
    expect(game.screen.value, const BagScreen(), reason: 'over another screen, nothing');
    expect(map.minimap, isFalse);
    game.dispose();
  });

  test("a column is its top block shaded by height, a liquid on it wins, and a swamp's is tinted", () async {
    final game = await _start();
    final at = IVec3.floor(game.player.position);
    final y = game.world.groundHeight(at.x, at.z);
    game.world.setBlockNamed(IVec3(at.x, y, at.z), 'stone');
    final plains = {MapPicture.biomeCell(at.x, at.z): 'plains'};
    final stone = game.world.blocks[game.world.blocks.indexOf('stone')];
    final shade = (0.55 + (y - 40) / 80.0).clamp(0.4, 1.2);
    int byte(double v) => (v * 255).round().clamp(0, 255);
    final grey = (byte(stone.r * shade) << 16) | (byte(stone.g * shade) << 8) | byte(stone.b * shade);
    expect(MapPicture.colourAt(game, at.x, at.z, plains), grey);
    final swamp = MapPicture.colourAt(game, at.x, at.z, {MapPicture.biomeCell(at.x, at.z): 'swamp'});
    expect(swamp, isNot(grey));
    expect((swamp >> 8) & 0xFF, greaterThan(swamp & 0xFF), reason: 'pulled towards the murky green');

    game.world.setBlockNamed(IVec3(at.x, y + 1, at.z), 'water');
    final water = game.world.blocks[game.world.blocks.indexOf('water')];
    expect(MapPicture.colourAt(game, at.x, at.z, plains), (byte(water.r) << 16) | (byte(water.g) << 8) | byte(water.b));
    game.dispose();
  });

  test('the picture covers the chunks loaded and those explored near the player, not the far ones', () async {
    final game = await _start();
    final here = ChunkStreamer.chunkOf(IVec3.floor(game.player.position));
    final near = (x: here.x + MapPicture.reach, z: here.z);
    final far = (x: here.x + MapPicture.reach + 1, z: here.z);
    WorldMap.of(game).restore(game, {
      'world': [
        [near.x, near.z],
        [far.x, far.z],
      ],
    });
    final covered = MapPicture.chunksOf(game);
    expect(covered, contains(here));
    expect(covered, contains(near));
    expect(covered, isNot(contains(far)));
    game.dispose();
  });

  test('the map marks the spawn, the structures found, the waypoints and the tamed mounts', () async {
    final game = await _start();
    final ruin = _nearest(game, 'ruins');
    await _standOn(game, ruin.x + 34.5, ruin.z + 0.5);
    expect(Structures.of(game).foundIn('world'), contains(ruin));

    final p = IVec3.floor(game.player.position);
    final cell = IVec3(p.x + 2, game.world.groundHeight(p.x + 2, p.z), p.z);
    game.world.setBlockNamed(cell, Waypoints.block);
    game.raise(BlockPlaced(Waypoints.block, cell));
    final horse = game.spawnMob('horse', game.player.position + Vector3(3, 0, 0))..tame(game.player);
    final wolf = game.spawnMob('wolf', game.player.position + Vector3(-3, 0, 0))..tame(game.player);
    _run(game, 1 / 60);

    final marks = MapPainter.marksOf(game);
    MapMark only(MapMarkShape shape) => marks.singleWhere((m) => m.shape == shape);
    expect(only(MapMarkShape.dot).label, 'Spawn');
    expect(
      marks.where((m) => m.shape == MapMarkShape.square && m.x == ruin.x + 0.5 && m.z == ruin.z + 0.5).single.label,
      'Ruin',
    );
    expect(only(MapMarkShape.diamond).label, 'Waypoint 1');
    expect(only(MapMarkShape.ring).label, horse.name, reason: 'a tamed wolf is no mount');
    expect(MapPainter.dotOf(wolf), MapPainter.petColour);
    expect(MapPainter.dotOf(game.spawnMob('zombie', game.player.position)), MapPainter.hostileColour);
    expect(MapPainter.dotOf(game.spawnMob('cow', game.player.position)), MapPainter.passiveColour);
    game.dispose();
  });

  testWidgets('the minimap shows under the quest, and the whole map is a screen with its legend', (tester) async {
    final game = (await tester.runAsync(() async {
      final game = await VoxelGame.startHeadless(gameSpec, options: _options);
      game.spawner.enabled = false;
      for (var i = 0; i < 600 && !game.ready; i++) {
        game.frame(1 / 60);
        await Future<void>.delayed(Duration.zero);
      }
      return game;
    }))!;
    game.input.wantCapture = true;
    game.input.lastDevice = InputDevice.keyboardMouse;
    await tester.pumpWidget(
      MaterialApp(
        home: GameSurface(
          game: game,
          world: const ColoredBox(color: Colors.black),
          hud: GameHud.builder,
        ),
      ),
    );
    expect(find.byType(Minimap), findsNothing);
    game.actions.tap(WorldMap.action);
    game.frame(1 / 30);
    await tester.pump();
    expect(find.byType(Minimap), findsOneWidget);
    expect(find.textContaining('M again: big map'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      game.frame(1 / 30);
      await tester.pump();
    }

    game.actions.tap(WorldMap.action);
    game.frame(1 / 30);
    await tester.pump();
    expect(game.screen.value, const DeclaredScreen(WorldMap.screen));
    expect(find.byType(Minimap), findsNothing);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapScreen(game))));
    expect(find.text('World map'), findsOneWidget);
    expect(find.textContaining('chunks explored'), findsOneWidget);
    for (final (_, _, name) in MapScreen.legend) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.tap(find.text('Back to the game'));
    expect(game.screen.value, isNull);
    game.dispose();
  });
}
