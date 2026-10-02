import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _cart = CartSpec(item: 'minecart');

BlockType _rail(String id, BlockShape shape) =>
    BlockType(id, color: 0x8A8478, shape: shape, solid: false, opaque: false, hardness: 0.7, drop: 'rail');

BlockType _powered(String id, BlockShape shape) =>
    BlockType(id, color: 0xB09048, shape: shape, solid: false, opaque: false, hardness: 0.5, drop: 'powered_rail');

/// Level grass at y 20 (the first air cell), no caves, no trees; rails of
/// every shape, powered rails both ways, a lever; a minecart item, two of
/// them in the bag.
VoxelGameSpec _spec() => VoxelGameSpec(
  blocks: [
    const BlockType('stone', color: 0x808080, hardness: 1.5),
    const BlockType('dirt', color: 0x74502F, hardness: 0.5),
    const BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
    const BlockType('rail', color: 0x8A8478, shape: BlockShape.railEw, solid: false, opaque: false, hardness: 0.7),
    _rail('rail_ns', BlockShape.railNs),
    _rail('rail_ne', BlockShape.railNe),
    _rail('rail_nw', BlockShape.railNw),
    _rail('rail_se', BlockShape.railSe),
    _rail('rail_sw', BlockShape.railSw),
    _rail('rail_slope_n', BlockShape.railSlopeN),
    _rail('rail_slope_e', BlockShape.railSlopeE),
    _rail('rail_slope_s', BlockShape.railSlopeS),
    _rail('rail_slope_w', BlockShape.railSlopeW),
    const BlockType('powered_rail', color: 0xB09048, shape: BlockShape.railEw, solid: false, hardness: 0.5),
    _powered('powered_rail_ns', BlockShape.railNs),
    _powered('powered_rail_on', BlockShape.railEw),
    _powered('powered_rail_ns_on', BlockShape.railNs),
    const BlockType('wire', color: 0x701010, shape: BlockShape.wire, solid: false, hardness: 0),
    const BlockType('wire_lit', color: 0xFF3020, shape: BlockShape.wire, solid: false, hardness: 0, drop: 'wire'),
    const BlockType('lever', color: 0x806040, shape: BlockShape.torch, solid: false, hardness: 0),
    const BlockType('lever_on', color: 0xE04030, shape: BlockShape.torch, solid: false, hardness: 0, drop: 'lever'),
    BlockType.liquid('water', color: 0x3366CC),
  ],
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  signals: const SignalSpec(
    wire: ('wire', 'wire_lit'),
    levers: {'lever': 'lever_on'},
    poweredRails: {'powered_rail': 'powered_rail_on', 'powered_rail_ns': 'powered_rail_ns_on'},
  ),
  items: const [ItemType('minecart', color: 0x8C8C94, stack: 1)],
  vehicles: const [_cart],
  player: const PlayerSpec(startingItems: {'minecart': 2}),
  sky: SkySpec.alwaysDay,
);

Future<VoxelGame> _start({bool authority = true}) async {
  final game = await VoxelGame.startHeadless(_spec(), authority: authority);
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

/// The cell on the ground [x], [z] cells from the player's feet.
IVec3 _ground(VoxelGame game, int x, int z) => IVec3.floor(game.player.position) + IVec3(x, 0, z);

/// Lays [block] at [from] and the [count] - 1 cells after it along [step].
void _line(VoxelGame game, IVec3 from, IVec3 step, int count, {String block = 'rail'}) {
  for (var i = 0; i < count; i++) {
    game.world.setBlockNamed(from + step * i, block);
  }
}

/// Where a cart is put on the rail at [cell]: its feet on the bars.
Vector3 _on(IVec3 cell) => Vector3(cell.x + 0.5, cell.y + Minecart.railTop, cell.z + 0.5);

/// The yaw that looks along [step].
double _yawAlong(IVec3 step) => math.atan2(-step.x.toDouble(), -step.z.toDouble());

const _east = IVec3(1, 0, 0), _north = IVec3(0, 0, -1);

void main() {
  test(
    'a rail laid turns to meet its neighbours, a curve and a slope up a block too; taken away, they turn back',
    () async {
      final game = await _start();
      final w = game.world;
      final base = _ground(game, 3, 0);
      _line(game, base, const IVec3(0, 0, 1), 3);
      for (var i = 0; i < 3; i++) {
        expect(w.blockNameAt(base + IVec3(0, 0, i)), 'rail_ns', reason: 'a line north-south');
      }
      w.setBlockNamed(base + const IVec3(1, 0, 2), 'rail');
      expect(w.blockNameAt(base + const IVec3(0, 0, 2)), 'rail_ne', reason: 'its end turns east to meet it');
      expect(w.blockNameAt(base + const IVec3(1, 0, 2)), 'rail');
      w.setBlockNamed(base + const IVec3(1, 0, 2), 'air');
      expect(w.blockNameAt(base + const IVec3(0, 0, 2)), 'rail_ns', reason: 'and back once it is gone');

      final step = base + const IVec3(6, 0, 0);
      w.setBlockNamed(step, 'stone');
      w.setBlockNamed(step + IVec3.up, 'rail');
      w.setBlockNamed(step - _east, 'rail');
      expect(w.blockNameAt(step - _east), 'rail_slope_e', reason: 'up onto the block');
      expect(w.blockNameAt(step + IVec3.up), 'rail');
      expect(game.rails.isRail(w.getBlock(step - _east)), isTrue);

      // A client lays what the host sends; it turns nothing itself.
      final client = await _start(authority: false);
      final at = _ground(client, 3, 0);
      _line(client, at, const IVec3(0, 0, 1), 2);
      expect(client.world.blockNameAt(at), 'rail');
      expect(client.world.blockNameAt(at + const IVec3(0, 0, 1)), 'rail');
    },
  );

  test('rails are checked at start: one block a kind, shape and state; both straights; a powered rail a rail', () {
    BlockRegistry<BlockType> blocks(List<BlockType> extra) =>
        _spec().copyWith(blocks: [..._spec().blocks, ...extra]).buildBlocks();
    final spec = _spec();
    expect(Rails(spec.buildBlocks(), spec.signals).graph.variants, hasLength(14));
    expect(
      () => Rails(blocks([_rail('rail_ns_again', BlockShape.railNs)]), spec.signals),
      throwsArgumentError,
      reason: 'two north-south rails of one kind',
    );
    expect(
      () => Rails(
        blocks([const BlockType('tram', color: 0, shape: BlockShape.railEw, solid: false, hardness: 0.7)]),
        spec.signals,
      ),
      throwsArgumentError,
      reason: 'a kind that cannot be laid north-south',
    );
    expect(
      () => Rails(
        blocks([const BlockType('booster', color: 0, hardness: 1)]),
        const SignalSpec(wire: ('wire', 'wire_lit'), poweredRails: {'booster': 'stone'}),
      ),
      throwsArgumentError,
      reason: 'a powered rail that is no rail',
    );
  });

  test(
    'its item puts it on the aimed rail, heading for the end nearest the look; elsewhere it says where it goes',
    () async {
      final game = await _start();
      final p = game.player;
      p.selectedSlot = p.inventory.find('minecart');
      p.yaw = _yawAlong(_east);
      p.pitch = -0.6;
      await _run(game, 0.05);
      game.input.tap(VoxelAction.use);
      await _run(game, 0.05);
      expect(game.vehicles, isEmpty);
      expect(game.notices.feed.last.text, 'A minecart goes on rails');

      final base = _ground(game, 2, 0);
      _line(game, base, _east, 6);
      await _run(game, 0.05);
      expect(game.rails.isRail(game.world.getBlock(p.aimedBlock!.block)), isTrue);
      game.input.tap(VoxelAction.use);
      await _run(game, 0.05);
      final cart = game.vehicles.single as Minecart;
      expect(cart.cell, p.aimedBlock!.block);
      expect(cart.heading, _east, reason: 'the player looks east');
      expect(cart.position.y, closeTo(base.y + Minecart.railTop, 1e-9), reason: 'on the bars');
      expect(cart.position.x, closeTo(cart.cell.x + 0.5, 1e-9), reason: 'in the middle of its rail');
      expect(cart.speed, 0.0);
      expect(p.inventory.countOf('minecart'), 1);

      final west = game.placeVehicle('minecart', _on(base + _east * 4), facing: _yawAlong(const IVec3(-1, 0, 0)))!;
      expect((west as Minecart).heading, const IVec3(-1, 0, 0));
      expect(west.facing, closeTo(math.pi / 2, 1e-9), reason: 'pointing along its line');
    },
  );

  test('alone, it rolls down a slope and coasts to rest along the flat', () async {
    final game = await _start();
    final base = _ground(game, 2, 0);
    final top = base + const IVec3(20, 0, 0);
    game.world.setBlockNamed(top, 'stone');
    game.world.setBlockNamed(top + IVec3.up, 'rail');
    _line(game, top - _east, const IVec3(-1, 0, 0), 20);
    expect(game.world.blockNameAt(top - _east), 'rail_slope_e');
    final cart = game.placeVehicle('minecart', _on(top - _east), facing: _yawAlong(_east))! as Minecart;
    await _run(game, 0.1);
    expect(cart.heading, const IVec3(-1, 0, 0), reason: 'headed uphill, it turns and rolls down');
    await _run(game, 0.7);
    expect(cart.cell.y, base.y, reason: 'down on the flat');
    expect(cart.speed, greaterThan(1.0));
    expect(cart.velocity.x, lessThan(-1.0), reason: 'its velocity is its speed along the line');
    await _run(game, 10.0);
    expect(cart.speed, 0.0, reason: 'the friction stops it');
    expect(cart.cell.x, inInclusiveRange(base.x + 1, top.x - 4));
    expect(cart.velocity.length, 0.0);
  });

  test('its rider pushes it along its heading by the move, and back the other way; the line\'s end stops it', () async {
    final game = await _start();
    final base = _ground(game, 2, 0);
    _line(game, base, _east, 12);
    final cart = game.placeVehicle('minecart', _on(base + _east * 3), facing: _yawAlong(_east))! as Minecart;
    final p = game.player
      ..ride(cart)
      ..yaw = _yawAlong(_east);
    final from = cart.position.clone();
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 1.0);
    game.input.hold(VoxelAction.moveForward, false);
    expect(cart.speed, closeTo(_cart.push - _cart.friction, 0.1), reason: 'a second\'s push, less the friction');
    expect(cart.position.x - from.x, greaterThan(0.5));
    expect(p.position.distanceTo(cart.seat()), lessThan(1e-6), reason: 'the rider sits in it');

    game.input.hold(VoxelAction.moveBack, true);
    await _run(game, 2.0);
    game.input.hold(VoxelAction.moveBack, false);
    expect(cart.heading, const IVec3(-1, 0, 0), reason: 'pushed back, it turns');

    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 6.0);
    game.input.hold(VoxelAction.moveForward, false);
    await _run(game, 0.1);
    expect(cart.cell, base + _east * 11, reason: 'at the last rail');
    expect(cart.position.x, closeTo(base.x + 12.0, 0.05), reason: 'at its end');
    expect(cart.speed, 0.0);
  });

  test('a powered rail on speeds it on, and one off brakes it', () async {
    final game = await _start();
    final base = _ground(game, 2, 0);
    game.world.setBlockNamed(base, 'lever_on');
    _line(game, base + _east, _east, 12, block: 'powered_rail');
    _line(game, base + _east * 13, _east, 20);
    await _run(game, 0.5);
    expect(game.world.blockNameAt(base + _east), 'powered_rail_on');
    expect(game.world.blockNameAt(base + _east * 12), 'powered_rail', reason: 'past the run\'s reach');
    final cart = game.placeVehicle('minecart', _on(base + _east), facing: _yawAlong(_east))! as Minecart;
    var fastest = 0.0;
    for (var i = 0; i < 300; i++) {
      await _run(game, 1 / 60);
      fastest = math.max(fastest, cart.speed);
    }
    expect(fastest, _cart.maxSpeed, reason: 'sped on to its top speed');
    expect(cart.speed, 0.0, reason: 'braked to a stop');
    expect(cart.cell.x, inInclusiveRange(base.x + 10, base.x + 12), reason: 'on the rails off');
  });

  test('a curve turns it; a rail turned under it keeps it on; with its rail gone it stays where it is', () async {
    final game = await _start();
    final base = _ground(game, 2, 0);
    _line(game, base, _east, 6);
    _line(game, base + _east * 5 + _north, _north, 10);
    expect(game.world.blockNameAt(base + _east * 5), 'rail_nw');
    final cart = game.placeVehicle('minecart', _on(base + _east), facing: _yawAlong(_east))! as Minecart;
    game.player
      ..ride(cart)
      ..yaw = _yawAlong(_east);
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 1.5);
    game.input.hold(VoxelAction.moveForward, false);
    await _run(game, 6.0);
    expect(cart.cell.x, base.x + 5);
    expect(cart.cell.z, lessThan(base.z), reason: 'round the curve, north');
    expect(cart.heading, _north);
    expect(cart.facing, closeTo(0.0, 1e-9), reason: 'pointing north');
    game.player.dismount();

    // Its rail turned under it (an east-west rail alone, rails laid north and south of it): it heads the nearest
    // way the new one goes.
    final cell = base + const IVec3(0, 0, 4);
    game.world.setBlockNamed(cell, 'rail');
    final alone = game.placeVehicle('minecart', _on(cell), facing: _yawAlong(_east))! as Minecart;
    game.world.setBlockNamed(cell + _north, 'rail');
    game.world.setBlockNamed(cell - _north, 'rail');
    expect(game.world.blockNameAt(cell), 'rail_ns');
    await _run(game, 0.1);
    expect(alone.heading.z.abs(), 1, reason: 'north or south, along its rail now');
    expect(alone.position.x, closeTo(cell.x + 0.5, 1e-9));

    game.world.setBlockNamed(cell, 'air');
    final left = alone.position.clone();
    await _run(game, 1.0);
    expect(alone.position, left);
    expect(alone.speed, 0.0);
    expect(alone.removed, isFalse);
  });

  test('the save keeps where it is on the rails, and how fast it goes', () async {
    final dir = Directory.systemTemp.createTempSync('voxel_carts');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final game = await _start();
    final base = _ground(game, 2, 0);
    _line(game, base, _east, 30);
    final cart = game.placeVehicle('minecart', _on(base + _east * 2), facing: _yawAlong(_east))! as Minecart;
    game.player
      ..ride(cart)
      ..yaw = _yawAlong(_east);
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 1.5);
    game.input.hold(VoxelAction.moveForward, false);
    game.player.dismount();
    expect(cart.speed, greaterThan(1.0));
    saves.save(game, 'carts');

    final loaded = await VoxelGame.startHeadless(_spec(), save: saves.read('carts'));
    final back = loaded.vehicles.single as Minecart;
    expect(back.cell, cart.cell);
    expect(back.heading, cart.heading);
    expect(back.along, cart.along);
    expect(back.speed, cart.speed);
    expect(back.position.distanceTo(cart.position), lessThan(1e-9));
    expect(() => back.restoreRow({'item': 'minecart'}), throwsA(isA<TypeError>()), reason: 'a row with no rail');
  });
}
