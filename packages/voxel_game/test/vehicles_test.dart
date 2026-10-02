import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _boat = BoatSpec(item: 'boat');

/// Level grass at y 20 (the first air cell), no caves, no trees; a nether to
/// travel to; a boat item, two of them in the bag.
VoxelGameSpec _spec({bool creative = false}) => VoxelGameSpec(
  blocks: const [
    BlockType('stone', color: 0x808080, hardness: 1.5),
    BlockType('dirt', color: 0x74502F, hardness: 0.5),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
    BlockType('planks', color: 0xB08850, hardness: 1.0),
    BlockType.liquid('water', color: 0x3366CC),
  ],
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  dimensions: const {
    'nether': WorldGenSpec(
      terrain: TerrainRecipe.flat(30),
      seaLevel: 5,
      caves: CaveSpec.none,
      biomes: [Biome('wastes', top: 'stone', precipitation: Precipitation.none)],
    ),
  },
  items: const [ItemType('boat', color: 0x8C6133, stack: 1)],
  vehicles: const [_boat],
  player: PlayerSpec(creative: creative, startingItems: const {'boat': 2}),
  sky: SkySpec.alwaysDay,
);

Future<VoxelGame> _start(VoxelGameSpec spec, {bool authority = true, SavedWorld? save}) async {
  final game = await VoxelGame.startHeadless(spec, authority: authority, save: save);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue, reason: 'the spawn chunk loads and the player stands on it');
  return game;
}

/// [seconds] of simulation, letting the chunk jobs land between frames.
Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

/// A pond three deep (water at y 17..19, its surface the top of 19) east of
/// the player, x +2..+13 and z -16..+4 from its feet; returns its middle
/// column's top water cell.
IVec3 _pond(VoxelGame game) {
  final feet = IVec3.floor(game.player.position);
  for (var x = 2; x <= 13; x++) {
    for (var z = -16; z <= 4; z++) {
      for (var y = 17; y <= 19; y++) {
        game.world.setBlockNamed(IVec3(feet.x + x, y, feet.z + z), 'water');
      }
    }
  }
  return IVec3(feet.x + 8, 19, feet.z - 6);
}

/// Where a boat floats over [cell]: its top's surface.
Vector3 _over(IVec3 cell) => Vector3(cell.x + 0.5, cell.y + 0.9, cell.z + 0.5);

/// Turns the player to look at [at].
void _lookAt(VoxelGame game, Vector3 at) {
  final p = game.player;
  final to = at - p.eyePosition;
  p.yaw = math.atan2(-to.x, -to.z);
  p.pitch = math.atan2(to.y, Vector3(to.x, 0, to.z).length);
}

/// Stands the player beside [at] (on the bank west of the pond), looking at it.
Future<void> _standBy(VoxelGame game, Vector3 at) async {
  final p = game.player;
  p.position = Vector3(at.x - 2.5, 20.0, at.z);
  await _run(game, 0.1);
  _lookAt(game, at + Vector3(0, 0.25, 0));
  await _run(game, 0.05);
}

int _dropped(VoxelGame game, String item) =>
    game.entities.whereType<ItemPickup>().where((d) => d.stack.id == item).fold(0, (n, d) => n + d.stack.count);

double _flatSpeed(Vector3 v) => math.sqrt(v.x * v.x + v.z * v.z);

class _Stranger implements Target {
  @override
  Vector3 position = Vector3.zero();

  @override
  Vector3 centre() => position;

  @override
  bool get isDead => false;

  @override
  double takeDamage(Damage damage) => 0.0;
}

void main() {
  test('a boat floats on water and settles at its surface; on land it falls and rests', () async {
    final game = await _start(_spec());
    final pond = _pond(game);
    final boat = game.placeVehicle('boat', _over(pond) + Vector3(0, 0.4, 0)) as Boat;
    final land = game.placeVehicle('boat', game.player.position + Vector3(-3, 2, 0));
    await _run(game, 6.0);
    final ys = <double>[];
    for (var i = 0; i < 60; i++) {
      await _run(game, 1 / 60);
      ys.add(boat.position.y);
    }
    expect(ys.reduce(math.min), greaterThan(19.6), reason: 'it does not sink');
    expect(ys.reduce(math.max), lessThan(20.1), reason: 'it does not fly off');
    expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(0.05), reason: 'settled, not bobbing about');
    expect(boat.afloat, isTrue);
    expect(land.onFloor, isTrue);
    expect(land.position.y, closeTo(20.0, 0.01));
  });

  test('its rider rows it forward and steers it; without a rider it coasts to rest', () async {
    final game = await _start(_spec());
    final pond = _pond(game);
    final boat = game.placeVehicle('boat', _over(pond));
    await _run(game, 2.0);
    final p = game.player..ride(boat);
    expect(p.riding, same(boat));
    expect(boat.rider, same(p));
    expect(p.position.distanceTo(boat.seat()), lessThan(1e-6));
    final from = boat.position.clone();
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 1.0);
    game.input.hold(VoxelAction.moveForward, false);
    expect(from.z - boat.position.z, greaterThan(3.0), reason: 'a second forward on water, its front -z');
    expect((boat.position.x - from.x).abs(), lessThan(0.1), reason: 'straight ahead');
    expect(p.position.distanceTo(boat.seat()), lessThan(1e-6), reason: 'the rider sits in it');
    expect(boat.facing, 0.0, reason: 'rowing turns nothing');
    game.input
      ..hold(VoxelAction.moveForward, true)
      ..hold(VoxelAction.moveRight, true);
    await _run(game, 1.0);
    game.input
      ..hold(VoxelAction.moveForward, false)
      ..hold(VoxelAction.moveRight, false);
    expect(boat.facing, closeTo(-_boat.turnSpeed, 0.05), reason: 'right turns it clockwise seen from above');
    expect(boat.velocity.x, greaterThan(1.0), reason: 'and on toward +x, where it points now');
    p.dismount();
    expect(boat.rider, isNull);
    expect(_flatSpeed(boat.velocity), greaterThan(0.5), reason: 'still moving when left');
    await _run(game, 4.0);
    expect(_flatSpeed(boat.velocity), lessThan(0.05), reason: 'it coasts to rest');
  });

  test('a use boards it, a sneak gets off beside it, and a seat taken throws', () async {
    final game = await _start(_spec());
    final pond = _pond(game);
    final boat = game.placeVehicle('boat', _over(pond));
    await _run(game, 1.0);
    await _standBy(game, boat.position);
    final p = game.player;
    expect(p.aimedVehicle, same(boat));
    expect(p.aimedMob, isNull);
    expect(game.input.touchTapPrimary, isFalse, reason: 'a finger\'s tap boards it, as a use does');
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.riding, same(boat));
    expect(p.aimedVehicle, isNull, reason: 'the rider does not aim at their own seat');
    expect(game.notices.feed.last.text, 'Riding the boat: sneak to get off');
    expect(() => p.ride(boat), throwsStateError, reason: 'the player rides already');
    game.input.tap(VoxelAction.sneak);
    await _run(game, 0.1);
    expect(p.riding, isNull);
    expect(boat.rider, isNull);
    final apart = Vector3(p.position.x - boat.position.x, 0, p.position.z - boat.position.z).length;
    expect(apart, closeTo(_boat.halfWidth + p.halfWidth + 0.2, 0.15), reason: 'beside it');

    boat.rider = _Stranger();
    expect(boat.takes(p), isFalse);
    expect(() => p.ride(boat), throwsStateError, reason: 'somebody rides it');
    expect(p.riding, isNull);
  });

  test('a swing breaks one nobody rides into its item; in creative into nothing', () async {
    for (final creative in [false, true]) {
      final game = await _start(_spec(creative: creative));
      final pond = _pond(game);
      final boat = game.placeVehicle('boat', _over(pond));
      await _run(game, 1.0);
      await _standBy(game, boat.position);
      expect(game.player.aimedVehicle, same(boat));
      game.input.tap(VoxelAction.attack);
      await _run(game, 0.05);
      expect(boat.removed, isTrue);
      expect(game.vehicles, isEmpty);
      expect(_dropped(game, 'boat'), creative ? 0 : 1);
    }
  });

  test('its item, used, puts it on the water along the aim; on land it only says where it goes', () async {
    final game = await _start(_spec());
    final pond = _pond(game);
    final p = game.player;
    p.selectedSlot = p.inventory.find('boat');
    expect(p.heldItem, 'boat');
    _lookAt(game, p.position + Vector3(-3, 0, 0));
    await _run(game, 0.05);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.05);
    expect(game.vehicles, isEmpty);
    expect(game.notices.feed.last.text, 'A boat goes on water');
    expect(p.inventory.countOf('boat'), 2);

    await _standBy(game, Vector3(pond.x + 0.5, 20.0, pond.z + 0.5));
    game.input.tap(VoxelAction.use);
    await _run(game, 0.05);
    final boat = game.vehicles.single;
    expect(boat, isA<Boat>());
    expect(IVec3.floor(boat.position).x, pond.x);
    expect(IVec3.floor(boat.position).z, pond.z);
    expect(boat.position.y, closeTo(pond.y + 0.9, 0.1), reason: 'on the surface');
    expect(boat.facing, closeTo(p.yaw, 1e-9), reason: 'pointing the way the player looks');
    expect(p.inventory.countOf('boat'), 1);
  });

  test('a client neither puts one down nor boards nor breaks one: the host owns them', () async {
    final game = await _start(_spec(), authority: false);
    final pond = _pond(game);
    final p = game.player;
    p.selectedSlot = p.inventory.find('boat');
    expect(() => game.placeVehicle('boat', _over(pond)), throwsStateError);
    await _standBy(game, Vector3(pond.x + 0.5, 20.0, pond.z + 0.5));
    game.input.tap(VoxelAction.use);
    await _run(game, 0.05);
    expect(game.vehicles, isEmpty);
    expect(p.inventory.countOf('boat'), 2);

    // One that reached it some other way (VA16's): neither boarded nor broken.
    final boat = game.add(Boat(_boat, _over(pond)));
    await _run(game, 0.5);
    await _standBy(game, boat.position);
    expect(p.aimedVehicle, same(boat));
    expect(boat.takes(p), isFalse);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.05);
    expect(p.riding, isNull);
    game.input.tap(VoxelAction.attack);
    await _run(game, 0.05);
    expect(boat.removed, isFalse);
  });

  test('a trip gets the rider off; the boat stays where it was left and is there on the way back', () async {
    final game = await _start(_spec());
    final pond = _pond(game);
    final boat = game.placeVehicle('boat', _over(pond), facing: 0.7);
    await _run(game, 1.0);
    game.player.ride(boat);
    await _run(game, 0.1);
    final left = boat.position.clone();
    game.travel('nether');
    expect(game.player.riding, isNull);
    expect(boat.rider, isNull);
    expect(game.vehicles, isEmpty);
    expect(game.parkedVehicles['world'], hasLength(1));
    for (var i = 0; i < 600 && game.travelState is Arriving; i++) {
      await _run(game, 1 / 60);
    }
    expect(game.vehicleRows.keys, ['world', 'nether'], reason: 'the nether has none, the world one parked');
    expect(game.vehicleRows['nether'], isEmpty);
    game.travel('world');
    final back = game.vehicles.single;
    expect(back, isNot(same(boat)));
    expect(back.position, left);
    expect(back.facing, 0.7);
    expect(game.parkedVehicles, isEmpty);
  });

  group('the save', () {
    (WorldSaves, Directory) newSaves() {
      final dir = Directory.systemTemp.createTempSync('voxel_vehicles');
      addTearDown(() => dir.deleteSync(recursive: true));
      return (WorldSaves(dir), dir);
    }

    test('keeps every dimension\'s vehicles, not their riders', () async {
      final (saves, dir) = newSaves();
      final spec = _spec();
      final game = await _start(spec);
      final pond = _pond(game);
      final boat = game.placeVehicle('boat', _over(pond), facing: -1.25);
      await _run(game, 1.0);
      game.player.ride(boat);
      game.restoreVehicles('nether', [
        {
          'item': 'boat',
          'pos': [3.5, 31.0, 4.5],
          'yaw': 2.0,
        },
      ]);
      expect(game.vehicles, hasLength(1), reason: 'the nether\'s is parked');
      saves.save(game, 'boats');
      final json = jsonDecode(File('${dir.path}/boats/game.json').readAsStringSync()) as Map<String, Object?>;
      expect(json['version'], 7);
      final rows = json['vehicles']! as Map<String, Object?>;
      expect((rows['world']! as List<Object?>).length, 1);
      expect((rows['nether']! as List<Object?>).length, 1);

      final loaded = await VoxelGame.startHeadless(spec, save: saves.read('boats'));
      final back = loaded.vehicles.single;
      expect(back.position, boat.position);
      expect(back.facing, -1.25);
      expect(back.rider, isNull);
      expect(loaded.player.riding, isNull);
      expect(loaded.parkedVehicles['nether']!.single['yaw'], 2.0);
    });

    test('a version 6 save, which kept no vehicle, still loads', () async {
      final (saves, dir) = newSaves();
      final spec = _spec();
      final game = await _start(spec);
      game.placeVehicle('boat', _over(_pond(game)));
      saves.save(game, 'old');
      final file = File('${dir.path}/old/game.json');
      final s = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      s['version'] = 6;
      s.remove('vehicles');
      file.writeAsStringSync(jsonEncode(s));

      final loaded = await VoxelGame.startHeadless(spec, save: saves.read('old'));
      expect(loaded.vehicles, isEmpty);
      expect(loaded.player.position, game.player.position);
    });

    test('a network hello, which carries no player, brings no vehicle', () async {
      final loaded = await VoxelGame.startHeadless(
        _spec(),
        save: const SavedWorld(7, {}, {'time': 3.0, 'timeOfDay': 0.5}),
      );
      expect(loaded.vehicles, isEmpty);
      expect(loaded.parkedVehicles, isEmpty);
    });
  });

  test('a spec\'s vehicles are checked: an item that exists, places no block, one vehicle an item', () {
    void check(List<VehicleSpec> vehicles) {
      final spec = _spec().copyWith(vehicles: vehicles);
      spec.checkVehicles(spec.buildItems(spec.buildBlocks()));
    }

    check(const [_boat]);
    expect(() => check(const [BoatSpec(item: 'raft')]), throwsArgumentError);
    expect(() => check(const [BoatSpec(item: 'planks')]), throwsArgumentError);
    expect(() => check(const [_boat, BoatSpec(item: 'boat', name: 'Canoe')]), throwsArgumentError);
    expect(_boat.name, 'Boat');
  });
}
