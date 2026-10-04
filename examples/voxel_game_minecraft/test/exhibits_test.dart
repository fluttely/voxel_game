import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/classes/class_system.dart';
import 'package:voxel_game_minecraft/src/classes/class_table.dart';
import 'package:voxel_game_minecraft/src/journal/tutorial.dart';
import 'package:voxel_game_minecraft/src/playground/exhibit_builder.dart';
import 'package:voxel_game_minecraft/src/playground/playground.dart';
import 'package:voxel_game_minecraft/src/playground/playground_zone.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/ui/game_hud.dart';
import 'package:voxel_game_minecraft/src/waypoints/waypoints.dart';

const _options = {'class': 'warrior', 'tutorial': 'on', 'playground': 'playground'};

final VoxelGameSpec _spec = gameSpec.copyWith(
  player: gameSpec.playerWith(_options),
  world: gameSpec.worldWith(_options),
);

/// A warrior's playground, as the title starts one, with no spawns of the
/// world's own; from [save] when given. Its hub is built.
Future<VoxelGame> _start({SavedWorld? save}) async {
  final game = await VoxelGame.startHeadless(_spec, options: _options, save: save, loadRadius: 3);
  game.spawner.enabled = false;
  await _until(game, () => Playground.of(game).built.contains('hub'));
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

/// Stands the player at the south edge of exhibit [id] until it is loaded
/// about them and built.
Future<PlaygroundZone> _visit(VoxelGame game, String id) async {
  final z = Playground.zone(id);
  final at = Vector3(z.cx + 0.5, Playground.floor + 0.1, z.cz + PlaygroundZone.half - 1.5);
  const h = PlaygroundZone.half;
  bool loaded() => [
    for (final (dx, dz) in const [(-h, -h), (h, -h), (-h, h), (h, h), (0, 0)])
      IVec3(z.cx + dx, Playground.floor, z.cz + dz),
  ].every(game.world.isLoaded);
  await _until(game, () => loaded() && Playground.of(game).built.contains(id), each: () => game.player.placeAt(at));
  game.player.placeAt(at);
  _run(game, Playground.lookEvery * 2);
  return z;
}

String _at(VoxelGame game, int x, int y, int z) => game.world.blockNameAt(IVec3(x, y, z));

Iterable<Mob> _tagged(VoxelGame game, String tag) =>
    game.mobs.where((m) => !m.isDead && !m.removed && m.data[Playground.exhibitKey] == tag);

Iterable<String> _told(VoxelGame game) => game.notices.feed.map((n) => n.text);

void _press(VoxelGame game, String action) {
  game.actions.tap(action);
  game.step(1 / 60);
}

void main() {
  test('a playground presses its plaza into the world; an open world does not', () {
    expect(gameSpec.worldWith(const {'playground': 'open'}), same(gameSpec.world));
    expect(gameSpec.worldWith(const {}), same(gameSpec.world));
    final g = _spec.world.compile(_spec.buildBlocks().ids, 1337);
    expect(g.surfaceHeight(8, 8), Playground.floor);
    expect(g.surfaceHeight(-60, 75), Playground.floor);
    expect(g.biomeAt(8, 8).name, 'plains');
    expect(gameSpec.screens[Playground.screen]!.menu, 'Playground');
  });

  test('a fresh playground starts at the hub with the showcase kit, the hub built and the tour set', () async {
    final game = await _start();
    final p = game.player;
    expect(Playground.isOn(game), isTrue);
    expect(p.position.distanceTo(Playground.spawn), lessThan(1.0));
    expect(p.spawnPoint, Playground.spawn);
    expect(p.inventory.slots.first!.id, classOf(_options).weapon, reason: "the class's weapon first");
    expect(p.inventory.countOf('glider'), 1);
    expect(p.level, 10);
    expect(ClassSystem.of(game).points, 10);
    expect(Tutorial.of(game).current, isNull, reason: 'a playground has no tutorial, whatever the form said');
    final hub = Playground.zone('hub');
    expect(_at(game, hub.cx, Playground.floor + 5, hub.cz - 1), 'ladder');
    expect(_at(game, hub.cx + 4, Playground.floor + 19, hub.cz + 4), 'glowstone');
    // The library: every item in the chests along the west side.
    final held = <String>{};
    for (var i = 0; _at(game, hub.cx - 10, Playground.floor, hub.cz - 6 + i * 2) == 'chest'; i++) {
      for (final s in game.blockRules.storeAt(IVec3(hub.cx - 10, Playground.floor, hub.cz - 6 + i * 2)).slots) {
        if (s != null) held.add(s.id);
      }
    }
    expect(held, {for (final t in game.items.all) t.id});
    final waypoints = Waypoints.of(game);
    expect(waypoints.all.map((w) => w.label), contains('Playground Hub'));
    final tour = Playground.of(game).tour;
    expect(tour, contains('Tour: Village'));
    expect(tour.where((t) => t.startsWith('Biome: ')), isNotEmpty);
    expect(waypoints.all.where(waypoints.isBare).map((w) => w.label), unorderedEquals(tour));
    _run(game, Waypoints.lookEvery + 0.1);
    expect(waypoints.all, hasLength(tour.length + 1), reason: 'a bare waypoint is never found gone');
    game.dispose();
  });

  test("an exhibit's card is up for its first seconds, and again in the next", () async {
    final game = await _start();
    final playground = Playground.of(game);
    expect(playground.current?.id, 'hub');
    expect(playground.cardVisible, isTrue);
    _run(game, Playground.cardSeconds + 0.5);
    expect(playground.cardVisible, isFalse);
    await _visit(game, 'water');
    expect(playground.current?.id, 'water');
    expect(playground.cardVisible, isTrue);
    game.dispose();
  });

  test('every exhibit is built as it loads, with what lives and rides there', () async {
    final game = await _start();
    final f = Playground.floor;
    final blocks = await _visit(game, 'blocks');
    expect(
      _at(game, blocks.cx - 18, f + 1, blocks.cz - 18),
      game.blocks.idOf(ExhibitBuilder.galleryBlocks(game.blocks).first),
    );
    final redstone = await _visit(game, 'redstone');
    _run(game, 0.5);
    expect(_at(game, redstone.cx - 10, f, redstone.cz - 14), 'lever_on');
    expect(_at(game, redstone.cx - 4, f, redstone.cz - 14), 'redstone_lamp_on', reason: 'the first lamp left lit');
    final rails = await _visit(game, 'rails');
    final start = ExhibitBuilder.railStart(rails);
    expect(_at(game, start.x + 11, f + 2, start.z), startsWith('rail'), reason: 'over the hill');
    expect(game.vehicles.where((v) => v.spec is CartSpec), hasLength(1));
    final water = await _visit(game, 'water');
    expect(_at(game, water.cx - 8, f - 3, water.cz), 'water');
    expect(game.vehicles.where((v) => v.spec is BoatSpec), hasLength(1));
    expect([for (var dx = 0; dx < 4; dx++) _at(game, water.cx + 12 + dx, f + 1, water.cz + 10)], contains('portal'));
    await _visit(game, 'farm');
    expect(_tagged(game, 'farm'), hasLength(ExhibitBuilder.pens.expand((p) => p).length));
    expect(game.mobs.where((m) => m.spec.id == 'villager'), hasLength(2));
    expect(game.mobs.where((m) => m.tamed).map((m) => m.spec.id), unorderedEquals(['horse', 'wolf', 'parrot']));
    await _visit(game, 'arena');
    expect(_tagged(game, 'arena').map((m) => m.spec.id), unorderedEquals(ExhibitBuilder.arenaMobs));
    final caves = await _visit(game, 'caves');
    expect(_at(game, caves.cx + 8, 13, caves.cz + 7), 'ladder', reason: 'the shaft goes down to the ore chamber');
    await _visit(game, 'building');
    expect(Playground.of(game).built, hasLength(Playground.zones.length));
    game.dispose();
  });

  test('the arena: a plate calls its boss once, and the gold button fills it again', () async {
    final game = await _start();
    final arena = await _visit(game, 'arena');
    final plate = ExhibitBuilder.bossPlateCell(arena, 2);
    game.player.placeAt(plate.centre..y = plate.y + 0.05);
    _run(game, 0.5);
    expect(_tagged(game, 'arena').where((m) => m.spec.id == 'yeti'), hasLength(1));
    expect(game.boss?.spec.id, 'yeti', reason: 'a boss of its species shows its bar');
    game.player.placeAt(Vector3(arena.cx + 0.5, Playground.floor + 0.1, arena.cz + 22.5));
    _run(game, 0.2);
    game.player.placeAt(plate.centre..y = plate.y + 0.05);
    _run(game, 0.2);
    expect(_tagged(game, 'arena').where((m) => m.spec.id == 'yeti'), hasLength(1));
    expect(_told(game), contains('The Yeti is already in the arena'));

    final zombie = _tagged(game, 'arena').firstWhere((m) => m.spec.id == 'zombie')..removed = true;
    _run(game, 0.1);
    expect(_tagged(game, 'arena').where((m) => m.spec.id == 'zombie'), isEmpty);
    expect(zombie.removed, isTrue);
    expect(game.useSignal(ExhibitBuilder.arenaRefillCell(arena)), isTrue, reason: 'the gold button pressed');
    _run(game, 0.2);
    expect(_tagged(game, 'arena').where((m) => m.spec.id == 'zombie'), hasLength(1));
    expect(_told(game), contains('The arena is full again'));
    game.dispose();
  });

  test('F7, F8 and F9 change the weather and the time and rebuild the exhibit stood in', () async {
    final game = await _start();
    _press(game, Playground.weatherAction);
    expect(game.weather.spell, WeatherKind.rain);
    _press(game, Playground.weatherAction);
    expect(game.weather.spell, WeatherKind.storm);
    _press(game, Playground.timeAction);
    expect(game.timeOfDay, closeTo(0.5, 0.01));
    expect(_told(game), contains('Time: Noon'));

    final building = await _visit(game, 'building');
    final wall = IVec3(building.cx - 18 + 1, Playground.floor + 1, building.cz - 18);
    expect(game.world.blockNameAt(wall), 'oak_planks');
    game.world.setBlockNamed(wall, 'air');
    game.player.placeAt(Vector3(building.cx + 0.5, Playground.floor + 0.1, building.cz + 0.5));
    _press(game, Playground.rebuildAction);
    expect(game.world.blockNameAt(wall), 'oak_planks');
    expect(game.player.position.z, closeTo(building.cz + PlaygroundZone.half - 1.5, 0.1));
    expect(_told(game), contains('Shapes & Building rebuilt'));
    game.dispose();
  });

  test('the save keeps what was built, and a reload brings the pens back without building again', () async {
    final dir = Directory.systemTemp.createTempSync('exhibits');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final game = await _start();
    await _visit(game, 'farm');
    final f = Playground.zone('farm');
    final post = IVec3(f.cx + 7, Playground.floor, f.cz - 14);
    expect(game.world.blockNameAt(post), 'oak_log');
    game.world.setBlockNamed(post, 'air');
    saves.save(game, 'playground');
    game.dispose();

    final loaded = await _start(save: saves.read('playground'));
    final playground = Playground.of(loaded);
    expect(playground.built, containsAll(['hub', 'farm']));
    expect(loaded.player.inventory.countOf('glider'), 1);
    expect(Waypoints.of(loaded).all.where(Waypoints.of(loaded).isBare), isNotEmpty);
    await _visit(loaded, 'farm');
    expect(loaded.world.blockNameAt(post), 'air', reason: "the player's change kept, not built over");
    expect(_tagged(loaded, 'farm'), hasLength(ExhibitBuilder.pens.expand((p) => p).length));
    expect(loaded.mobs.where((m) => m.tamed), hasLength(3), reason: 'the companions came back with the save, once');
    loaded.dispose();
  });

  test('nothing runs out in a playground, and the menu lists its buttons there only', () async {
    final game = await _start();
    final classes = ClassSystem.of(game);
    expect(classes.endless, isTrue);
    final stamina = classes.stamina;
    _press(game, 'dodge');
    expect(classes.stamina, stamina);
    final hub = Waypoints.of(game).all.firstWhere((w) => w.label == 'Playground Hub');
    classes.mana = 0.0;
    game.player.placeAt(Vector3(60.5, Playground.floor + 0.1, 60.5));
    expect(Waypoints.of(game).travel(game, hub), isTrue, reason: 'a trip from afar is free');
    expect(gameSpec.screens[Playground.screen]!.listedIn(game), isTrue);
    game.dispose();

    const open = {'class': 'warrior', 'tutorial': 'off'};
    final world = await VoxelGame.startHeadless(gameSpec.copyWith(player: gameSpec.playerWith(open)), options: open);
    world.spawner.enabled = false;
    await _until(world, () => world.ready);
    _run(world, 1.0);
    expect(Playground.isOn(world), isFalse);
    expect(ClassSystem.of(world).endless, isFalse);
    expect(Playground.of(world).built, isEmpty, reason: 'an open world builds nothing');
    expect(gameSpec.screens[Playground.screen]!.listedIn(world), isFalse);
    world.dispose();
  });

  test("the crosshair names the block it is on, in a playground", () async {
    final game = await _start();
    final hub = Playground.zone('hub');
    game.player
      ..placeAt(Vector3(hub.cx + 1.5, Playground.floor + 0.1, hub.cz + 6.5))
      ..yaw = 0.0
      ..pitch = 0.0;
    _run(game, 0.1);
    expect(GameHud.aimedBlockOf(game), 'Stone Bricks', reason: "the tower's wall ahead");
    game.dispose();
  });
}
