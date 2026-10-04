import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
  BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
  BlockType('planks', color: 0xB08850, hardness: 1.0, tool: 'axe'),
  BlockType.liquid('water', color: 0x3366CC),
  BlockType('wire', color: 0x701010, shape: BlockShape.wire, solid: false, hardness: 0),
  BlockType('wire_lit', color: 0xFF3020, shape: BlockShape.wire, solid: false, hardness: 0, light: 3),
  BlockType('lever', color: 0x806040, shape: BlockShape.torch, solid: false, hardness: 0),
  BlockType('lever_on', color: 0xA08060, shape: BlockShape.torch, solid: false, hardness: 0),
  BlockType('lamp', color: 0x604020),
  BlockType('lamp_lit', color: 0xFFD080, light: 15),
];

const _spec = VoxelGameSpec(
  blocks: _blocks,
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  sky: SkySpec.alwaysDay,
  mobs: [
    MobSpec('dummy', hp: 10, brain: []),
    MobSpec('biter', hp: 10, speed: 3, brain: [MeleeAttack(damage: 2), Hunt(range: 20)]),
  ],
);

const _storeSpec = VoxelGameSpec(
  blocks: [
    ..._blocks,
    BlockType('chest', color: 0x8A5A2A, hardness: 2.0, storage: Storage(slots: 9)),
  ],
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  sky: SkySpec.alwaysDay,
);

/// [_spec] under a sky that stays clear until the host sets it, each spell
/// held for a long while.
const _skySpec = VoxelGameSpec(
  blocks: _blocks,
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  sky: SkySpec(
    startTime: 0.5,
    cycle: false,
    weather: WeatherSpec(odds: WeatherOdds(clear: 1, rain: 0, storm: 0), minSpell: 1000, maxSpell: 1000),
  ),
);

/// [_spec] with creatures to tame — a wolf that heels, one that is hardly
/// ever won over, a horse to ride — and three bones for every player.
const _petSpec = VoxelGameSpec(
  blocks: _blocks,
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  sky: SkySpec.alwaysDay,
  items: [ItemType('bone', color: 0xEEEEDD)],
  player: PlayerSpec(startingItems: {'bone': 3}),
  mobs: [
    MobSpec('wolf', hp: 12, speed: 4.0, brain: [], tameWith: ['bone'], tamedBrain: [Heel()]),
    MobSpec('shy', hp: 4, brain: [], tameWith: ['bone'], tameChance: 1e-9, tamedBrain: [Heel()]),
    MobSpec(
      'horse',
      hp: 20,
      speed: 5.0,
      halfWidth: 0.5,
      height: 1.6,
      brain: [],
      tameWith: ['bone'],
      tamedBrain: [MountWait()],
      mount: MountSpec(seat: 1.0),
    ),
  ],
);

/// [_spec] at midnight, the clock stopped, with beds, shears for every
/// player and a sheep to shear.
const _farmSpec = VoxelGameSpec(
  blocks: [
    ..._blocks,
    BlockType('bed', color: 0xC03030, shape: BlockShape.slab, hardness: 0.5, bed: true),
  ],
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  sky: SkySpec(startTime: 0.0, cycle: false),
  items: [
    ItemType('shears', color: 0xC0C0C8, tool: 'shears', stack: 1, durability: 40),
    ItemType('wool', color: 0xEEEEEE),
  ],
  player: PlayerSpec(startingItems: {'shears': 1}),
  mobs: [MobSpec('sheep', hp: 8, halfWidth: 0.45, height: 1.2, brain: [], fleece: Fleece('wool'))],
);

BlockType _rail(String id, BlockShape shape) =>
    BlockType(id, color: 0x8A8478, shape: shape, solid: false, opaque: false, hardness: 0.7, drop: 'rail');

/// [_spec]'s ground with rails, a boat and a minecart (two boats and a cart
/// for every player), and a nether to travel to.
final _rideSpec = VoxelGameSpec(
  blocks: [
    ..._blocks,
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
  sky: SkySpec.alwaysDay,
  items: const [ItemType('boat', color: 0x8C6133, stack: 1), ItemType('minecart', color: 0x8C8C94, stack: 1)],
  vehicles: const [
    BoatSpec(item: 'boat'),
    CartSpec(item: 'minecart'),
  ],
  player: const PlayerSpec(startingItems: {'boat': 2, 'minecart': 1}),
);

/// [_spec] with a rod for every player, and nothing ever biting.
const _fishSpec = VoxelGameSpec(
  blocks: _blocks,
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  sky: SkySpec.alwaysDay,
  items: [ItemType('fishing_rod', color: 0x9E7340, stack: 1), ItemType('raw_fish', color: 0x99B3BF)],
  fishing: FishingSpec(
    rod: 'fishing_rod',
    catches: LootTable.oneOf([LootEntry('raw_fish', 1, 1, 1.0)]),
    minWait: 1000,
    maxWait: 1000,
    xp: 0,
  ),
  player: PlayerSpec(startingItems: {'fishing_rod': 1}),
);

/// [game]'s player, rod in hand, stands 3.5 m west of the water at [cell]
/// and casts at it.
Future<void> _cast(List<VoxelGame> games, VoxelGame game, IVec3 cell) async {
  final p = game.player..selectedSlot = game.player.inventory.find('fishing_rod');
  p.position = Vector3(cell.x - 3.0, 20.0, cell.z + 0.5);
  await _run(games, 0.1);
  _lookAt(game, Vector3(cell.x + 0.5, cell.y + 0.9, cell.z + 0.5));
  game.input.tap(VoxelAction.use);
  await _run(games, 0.05);
  expect(p.bobber, isNotNull, reason: 'cast');
}

/// A pond three deep the host digs east of its player (water at y 17..19),
/// x +2..+13 and z -24..+4 from its feet; returns a top water cell 6 north
/// of its middle row.
IVec3 _pond(VoxelGame host) {
  final feet = IVec3.floor(host.player.position);
  for (var x = 2; x <= 13; x++) {
    for (var z = -24; z <= 4; z++) {
      for (var y = 17; y <= 19; y++) {
        host.world.setBlockNamed(IVec3(feet.x + x, y, feet.z + z), 'water');
      }
    }
  }
  return IVec3(feet.x + 8, 19, feet.z - 6);
}

/// Where a boat floats over [cell]: its top's surface.
Vector3 _over(IVec3 cell) => Vector3(cell.x + 0.5, cell.y + 0.9, cell.z + 0.5);

/// Turns [game]'s player to look at [at].
void _lookAt(VoxelGame game, Vector3 at) {
  final p = game.player;
  final to = at - p.eyePosition;
  p.yaw = math.atan2(-to.x, -to.z);
  p.pitch = math.atan2(to.y, Vector3(to.x, 0, to.z).length);
}

/// Stands [game]'s player on the ground 2.5 m west of [at], looking at it.
Future<void> _standBy(List<VoxelGame> games, VoxelGame game, Vector3 at) async {
  game.player.position = Vector3(at.x - 2.5, 20.0, at.z);
  await _run(games, 0.1);
  _lookAt(game, at + Vector3(0, 0.25, 0));
  await _run(games, 0.05);
}

/// [game]'s replica of the host's vehicle [v].
Vehicle _copyOf(VoxelGame game, Vehicle v) => game.vehicles.singleWhere((c) => c.netId == v.netId);

/// Turns [game]'s player to look at [m]'s middle.
void _face(VoxelGame game, Mob m) {
  final p = game.player;
  final to = m.centre() - p.eyePosition;
  p.yaw = -Vector3(0, 0, -1).angleToSigned(Vector3(to.x, 0, to.z).normalized(), Vector3(0, 1, 0));
  p.pitch = math.atan2(to.y, Vector3(to.x, 0, to.z).length);
}

/// [game]'s replica of the host's creature [mob].
Mob _replicaOf(VoxelGame game, Mob mob) => game.mobs.singleWhere((m) => m.netId == mob.netId);

/// A chest the host places beside its player, with [stone] stone in its
/// first slot, every game told of it.
Future<IVec3> _chest(VoxelGame host, List<VoxelGame> clients, {int stone = 10}) async {
  final cell = IVec3.floor(host.player.position) + const IVec3(2, 0, 0);
  host.world.setBlockNamed(cell, 'chest');
  if (stone > 0) host.blockRules.storeAt(cell).add('stone', stone);
  await _run([host, ...clients], 0.3);
  for (final c in clients) {
    expect(c.world.blockNameAt(cell), 'chest');
  }
  return cell;
}

/// Both games advance [seconds], the sockets flushing between frames.
Future<void> _run(List<VoxelGame> games, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    for (final g in games) {
      g.frame(1 / 60);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Waits, the sockets flushing and no game stepping, until [done].
Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(done(), isTrue, reason: 'the messages crossed');
}

/// A host and [clients] clients of [spec], all ready by its player.
Future<(VoxelGame, HostSession, List<VoxelGame>)> _session(int clients, {VoxelGameSpec spec = _spec}) async {
  final host = await VoxelGame.startHeadless(spec);
  host.spawner.enabled = false;
  await _run([host], 1.0);
  final session = await host.host(port: 0);
  final joined = [
    for (var i = 0; i < clients; i++)
      await VoxelGame.joinGame(spec, '127.0.0.1', port: session.net.port, headless: true),
  ];
  await _run([host, ...joined], 2.0);
  for (final c in joined) {
    expect(c.ready, isTrue);
  }
  return (host, session, joined);
}

Future<void> _close(HostSession session, List<VoxelGame> clients) async {
  for (final c in clients) {
    await c.session!.close();
  }
  await session.close();
}

ClientSession _client(VoxelGame game) => game.session! as ClientSession;

void main() {
  test('a client joins a host: the world, edits both ways, players and what they hold, mobs, hits and hurts', () async {
    final host = await VoxelGame.startHeadless(_spec);
    host.spawner.enabled = false;
    await _run([host], 1.0);
    expect(host.ready, isTrue);
    final start = IVec3.floor(host.player.position);
    final before = start + const IVec3(2, 0, 0);
    host.world.setBlockNamed(before, 'planks'); // an edit made before anyone joins
    final session = await host.host(port: 0);

    final client = await VoxelGame.joinGame(_spec, '127.0.0.1', port: session.net.port, headless: true);
    await _run([host, client], 2.0);
    expect(client.ready, isTrue);
    expect(client.world.blockNameAt(before), 'planks', reason: 'the hello carries the edits so far');

    final byHost = start + const IVec3(0, 0, 3);
    host.world.setBlockNamed(byHost, 'stone');
    final byClient = start + const IVec3(0, 0, -3);
    client.world.setBlockNamed(byClient, 'planks');
    await _run([host, client], 0.5);
    expect(client.world.blockNameAt(byHost), 'stone');
    expect(host.world.blockNameAt(byClient), 'planks');

    expect(host.remotePlayers, hasLength(1));
    expect(client.remotePlayers, hasLength(1), reason: "the client sees the host's player");
    expect(host.remotePlayers.single.position.distanceTo(client.player.position), lessThan(0.5));

    // A host mob is a replica on the client; the client's hit lands on the host.
    final dummy = host.spawnMob('dummy', host.player.position + Vector3(0, 0, -6));
    await _run([host, client], 0.5);
    final replica = client.mobs.singleWhere((m) => m.netId == dummy.netId);
    expect(replica.replica, isTrue);
    expect(replica.position.distanceTo(dummy.position), lessThan(0.5));
    expect(client.damageNumbers.shown, isEmpty, reason: 'the first state is where a replica starts, not a hit');
    replica.takeDamage(Damage(4, from: client.player.position, attacker: client.player));
    await _run([host, client], 0.3);
    expect(dummy.hp, 6);
    expect(replica.hp, 6, reason: "the host's health comes back");
    expect([for (final n in host.damageNumbers.shown) n.amount], [4]);
    expect([for (final n in client.damageNumbers.shown) n.amount], [4], reason: 'the health it lost is the hit');
    expect(replica.sinceHurt, lessThan(0.3));

    // What each player holds crosses with its pose, both ways.
    host.player.inventory.add('stone', 3);
    client.player.inventory.add('planks', 2);
    expect([host.player.heldItem, client.player.heldItem], ['stone', 'planks']);
    await _run([host, client], 0.3);
    expect(host.remotePlayers.single.heldItem, 'planks');
    expect(client.remotePlayers.single.heldItem, 'stone');

    // A host hunter bites the client's player through its puppet (the host's
    // own player walked away, or it would be bitten first).
    host.player.position = host.player.position + Vector3(0, 0, 30);
    host.spawnMob('biter', client.player.position + Vector3(3, 0, 0));
    final hp = client.player.hp, hostHp = host.player.hp;
    await _run([host, client], 3.0);
    expect(client.player.hp, lessThan(hp));
    expect(host.player.hp, hostHp);

    await client.session!.close();
    await _run([host], 0.3);
    expect(host.remotePlayers, isEmpty, reason: 'a client that leaves is gone');
    await session.close();
  });

  test("a step's edits leave together, as one message, in the order they were made", () async {
    final host = await VoxelGame.startHeadless(_spec);
    host.spawner.enabled = false;
    await _run([host], 1.0);
    final session = await host.host(port: 0);
    final client = await VoxelGame.joinGame(_spec, '127.0.0.1', port: session.net.port, headless: true);
    final watcher = await joinHost('127.0.0.1', port: session.net.port);
    final heard = <Map<String, Object?>>[];
    watcher.connection.listen(heard.add);
    await _run([host, client], 2.0);
    expect(client.ready, isTrue);

    // A burst between two steps, as a client's edits arrive: 50 cells, the
    // first one edited twice.
    final corner = IVec3.floor(host.player.position) + const IVec3(-5, 3, 5);
    final cells = [for (var i = 0; i < 50; i++) corner + IVec3(i % 10, i ~/ 10, 0)];
    for (final c in cells) {
      host.world.setBlockNamed(c, 'planks');
    }
    host.world.setBlockNamed(cells.first, 'stone');
    await _run([host, client], 0.5);

    final edits = heard.where((m) => m['t'] == 'edits').toList();
    expect(edits, hasLength(1), reason: 'one message for the burst, not one per cell');
    final e = edits.single['e']! as List<Object?>;
    expect(e, hasLength(51 * 4));
    final stone = host.blocks.indexOf('stone');
    expect(e.sublist(e.length - 4), [cells.first.x, cells.first.y, cells.first.z, stone]);
    expect(client.world.blockNameAt(cells.first), 'stone', reason: 'a cell edited twice ends as the last edit');
    for (final c in cells.skip(1)) {
      expect(client.world.blockNameAt(c), 'planks');
    }

    await watcher.connection.close();
    await client.session!.close();
    await session.close();
  });

  test("a client's edit where the host has not loaded the world reaches the other clients", () async {
    final host = await VoxelGame.startHeadless(_spec);
    host.spawner.enabled = false;
    await _run([host], 1.0);
    final session = await host.host(port: 0);
    final a = await VoxelGame.joinGame(_spec, '127.0.0.1', port: session.net.port, headless: true);
    final b = await VoxelGame.joinGame(_spec, '127.0.0.1', port: session.net.port, headless: true);
    await _run([host, a, b], 2.0);
    expect(a.ready && b.ready, isTrue);

    // Both clients walk far from the host, out of the host's loaded world.
    final far = host.player.position + Vector3(300, 0, 0);
    a.player.position = far.clone();
    b.player.position = far.clone();
    await _run([host, a, b], 2.0);
    final cell = IVec3.floor(a.player.position) + const IVec3(0, 2, 2);
    expect(host.world.isLoaded(cell), isFalse, reason: 'the edit must land where the host has no chunk');
    expect(b.world.isLoaded(cell), isTrue);

    a.world.setBlockNamed(cell, 'planks');
    await _run([host, a, b], 0.5);
    expect(b.world.blockNameAt(cell), 'planks', reason: 'the host passes on an edit it could only store');
    expect(a.world.blockNameAt(cell), 'planks');

    await a.session!.close();
    await b.session!.close();
    await session.close();
  });

  test("a client's edit shows at once and the host's ack confirms it", () async {
    final (host, session, [a, b]) = await _session(2);
    final cell = IVec3.floor(a.player.position) + const IVec3(2, 1, 2);
    a.world.setBlockNamed(cell, 'planks');
    expect(a.world.blockNameAt(cell), 'planks', reason: 'the prediction');
    expect(_client(a).pendingEdits, 1);
    await _run([host, a, b], 0.5);
    expect(_client(a).pendingEdits, 0);
    expect(_client(a).rollbacks, 0);
    for (final g in [host, a, b]) {
      expect(g.world.blockNameAt(cell), 'planks');
    }
    await _close(session, [a, b]);
  });

  test('two clients on one cell: the host takes the first, refuses the second, which rolls back', () async {
    final (host, session, [a, b]) = await _session(2);
    final cell = IVec3.floor(a.player.position) + const IVec3(2, 1, 2);
    a.world.setBlockNamed(cell, 'planks');
    b.world.setBlockNamed(cell, 'stone');
    a.frame(1 / 30);
    b.frame(1 / 30);
    // The host does not step, so it echoes nothing: only the acks cross.
    await _settle(() => _client(a).pendingEdits == 0 && _client(b).pendingEdits == 0);
    final standing = host.world.blockNameAt(cell);
    expect(standing, isIn(['planks', 'stone']));
    expect(a.world.blockNameAt(cell), standing);
    expect(b.world.blockNameAt(cell), standing);
    expect(_client(a).rollbacks + _client(b).rollbacks, 1, reason: 'the refused one rolled back to the host\'s');
    await _run([host, a, b], 0.5);
    for (final g in [host, a, b]) {
      expect(g.world.blockNameAt(cell), standing);
    }
    await _close(session, [a, b]);
  });

  test("the host's echo of a cell waits while a prediction owns it", () async {
    final (host, session, [a]) = await _session(1);
    final cell = IVec3.floor(a.player.position) + const IVec3(2, 1, 2);
    // The host's echo carries stone, then air; it leaves before the client's
    // request arrives, which the host's air then takes.
    host.world.setBlockNamed(cell, 'stone');
    host.world.setBlockNamed(cell, 'air');
    a.world.setBlockNamed(cell, 'planks');
    host.frame(1 / 30);
    a.frame(1 / 30);
    await _settle(() => _client(a).pendingEdits == 0);
    expect(host.world.blockNameAt(cell), 'planks');
    expect(a.world.blockNameAt(cell), 'planks', reason: 'the echo older than the ack did not land');
    expect(_client(a).rollbacks, 0);
    await _close(session, [a]);
  });

  test("a client's lever is an edit the host's circuits answer: the lamp lights everywhere", () async {
    final spec = _spec.copyWith(
      signals: () =>
          const SignalSpec(wire: ('wire', 'wire_lit'), levers: {'lever': 'lever_on'}, lamps: {'lamp': 'lamp_lit'}),
    );
    final (host, session, [a, b]) = await _session(2, spec: spec);
    expect(a.signals, isNull, reason: 'a client runs no circuits');
    a.player
      ..pitch = -0.9
      ..inventory.add('planks', 3);
    await _run([host, a, b], 0.2);
    final lever = a.player.aimedBlock!.block;
    host.world.setBlockNamed(lever + const IVec3(0, -1, 0), 'lamp');
    host.world.setBlockNamed(lever, 'lever');
    await _run([host, a, b], 0.5);
    expect(a.player.aimedBlock!.block, lever);

    a.input.tap(VoxelAction.use);
    await _run([host, a, b], 1.0);
    for (final g in [host, a, b]) {
      expect(g.world.blockNameAt(lever), 'lever_on');
      expect(g.world.blockNameAt(lever + const IVec3(0, -1, 0)), 'lamp_lit');
    }
    expect(a.player.inventory.countOf('planks'), 3, reason: 'the use flipped the lever, it built nothing');
    expect(_client(a).rollbacks, 0);
    await _close(session, [a, b]);
  });

  test("a client's drop is the host's: it lies on the host and the other client draws it where it lands", () async {
    final (host, session, [a, b]) = await _session(2);
    // Out of everyone's reach, so nobody takes it.
    final cell = IVec3.floor(a.player.position) + const IVec3(8, -1, 0);
    expect(a.world.blockNameAt(cell), 'grass');
    a.breakBlock(cell, byPlayer: true);
    expect(a.entities.whereType<ItemPickup>(), isEmpty, reason: 'the host makes it');
    expect(a.dropItem('planks', 2, a.player.position + Vector3(0, 0.5, -8), throwVelocity: Vector3.zero()), isNull);
    await _run([host, a, b], 2.0);

    final drops = {for (final d in host.entities.whereType<ItemPickup>()) d.item: d};
    expect(
      drops.keys,
      unorderedEquals(['dirt', 'planks']),
      reason: "the block's loot, rolled by the client, and a throw",
    );
    expect(drops['planks']!.count, 2);
    for (final d in drops.values) {
      expect(d.replica, isFalse);
      expect(d.netId, isNot(0));
    }
    for (final g in [a, b]) {
      final replicas = g.entities.whereType<ItemPickup>().toList();
      expect(replicas, hasLength(2));
      for (final r in replicas) {
        final d = drops[r.item]!;
        expect(r.replica, isTrue);
        expect(r.netId, d.netId);
        expect(r.position.distanceTo(d.position), lessThan(0.1), reason: 'its poses followed it to where it lies');
      }
    }
    expect(drops['dirt']!.position.y, lessThan(cell.y + 1.5), reason: 'it fell from where it was tossed up');
    await _close(session, [a, b]);
  });

  test('the host decides the pickup: the nearest player whose bag takes it, a client as well as its own', () async {
    final (host, session, [a, b]) = await _session(2);
    final at = host.player.position.clone();
    a.player.position = at + Vector3(0, 0, 30);
    b.player.position = at + Vector3(3, 0, 0);
    await _run([host, a, b], 0.5);
    expect(host.remotePlayers.firstWhere((r) => r.peer == _client(b).peer).bag, isNotNull, reason: 'b declared it');

    // Two metres from the host's player and one from b's.
    host.dropItem('stone', 2, at + Vector3(2, 0.2, 0), throwVelocity: Vector3.zero());
    await _run([host, a, b], 0.3);
    expect(b.entities.whereType<ItemPickup>().single.replica, isTrue);
    await _run([host, a, b], 1.5);
    expect(b.player.inventory.countOf('stone'), 2, reason: "the host handed it to b's bag");
    expect(host.player.inventory.countOf('stone'), 0);
    for (final g in [host, a, b]) {
      expect(g.entities.whereType<ItemPickup>(), isEmpty, reason: 'taken, so gone everywhere');
    }

    // One metre from the host's player and two from b's.
    host.dropItem('planks', 1, at + Vector3(1, 0.2, 0), throwVelocity: Vector3.zero());
    await _run([host, a, b], 1.5);
    expect(host.player.inventory.countOf('planks'), 1);
    expect(b.player.inventory.countOf('planks'), 0);
    for (final g in [host, a, b]) {
      expect(g.entities.whereType<ItemPickup>(), isEmpty);
    }
    await _close(session, [a, b]);
  });

  test("what a client's bag no longer takes comes back to the puppet's feet; a full bag pulls nothing", () async {
    final (host, session, [a]) = await _session(1);
    final at = host.player.position.clone();
    host.player.position = at + Vector3(0, 0, 30);
    a.player.position = at + Vector3(10, 0, 0);
    await _run([host, a], 0.5);
    final puppet = host.remotePlayers.single;
    expect(puppet.roomFor(ItemStack('stone', 3)), 3, reason: 'empty, as declared');

    // Full on the client, still empty as the host knows it: the client does
    // not step, so it declares nothing until the stack has crossed.
    a.player.inventory.add('planks', 100000);
    expect(a.player.inventory.roomFor('stone', 1), 0);
    host.dropItem('stone', 3, puppet.position + Vector3(0.5, 0.2, 0), throwVelocity: Vector3.zero());
    await _run([host], 1.5);
    expect(a.player.inventory.countOf('stone'), 0);
    final back = host.entities.whereType<ItemPickup>().single;
    expect([back.item, back.count], ['stone', 3], reason: 'give_rest brought all of it back');
    expect(back.wait, greaterThan(ItemPickup.delay));
    expect(back.position.distanceTo(puppet.position), lessThan(1.5), reason: "at the puppet's feet");

    // Now the client declares its full bag: the drop stays where it is.
    await _run([host, a], 3.0);
    expect(puppet.roomFor(ItemStack('stone', 3)), 0);
    expect(host.entities.whereType<ItemPickup>().single, same(back));
    expect(back.position.distanceTo(puppet.position), lessThan(1.5));
    expect(a.player.inventory.countOf('stone'), 0);
    expect(a.entities.whereType<ItemPickup>().single.netId, back.netId);
    await _close(session, [a]);
  });

  test("a far client's drop waits where the host has no world, and its player takes it", () async {
    final (host, session, [a]) = await _session(1);
    a.player.position = host.player.position + Vector3(300, 0, 0);
    await _run([host, a], 2.0);
    final cell = IVec3.floor(a.player.position) + const IVec3(2, -1, 0);
    expect(host.world.isLoaded(cell), isFalse);
    expect(a.world.blockNameAt(cell), 'grass');
    a.breakBlock(cell, byPlayer: true);
    await _run([host, a], 0.2);
    final drop = host.entities.whereType<ItemPickup>().single;
    expect(drop.position.y, greaterThan(cell.y), reason: 'not fallen through the world the host does not have');
    await _run([host, a], 2.0);
    expect(a.player.inventory.countOf('dirt'), 1);
    expect(host.entities.whereType<ItemPickup>(), isEmpty);
    await _close(session, [a]);
  });

  test('the hello brings the drops there are', () async {
    final host = await VoxelGame.startHeadless(_spec);
    host.spawner.enabled = false;
    await _run([host], 1.0);
    final lying = host.dropItem('planks', 4, host.player.position + Vector3(8, 0.5, 0), throwVelocity: Vector3.zero())!;
    await _run([host], 1.0);
    final session = await host.host(port: 0);
    final client = await VoxelGame.joinGame(_spec, '127.0.0.1', port: session.net.port, headless: true);

    // Before the client's first step.
    final r = client.entities.whereType<ItemPickup>().single;
    expect(r.replica, isTrue);
    expect(r.netId, lying.netId);
    expect([r.item, r.count], ['planks', 4]);
    expect(r.position.distanceTo(lying.position), lessThan(0.01));
    await _run([host, client], 0.5);
    expect(client.entities.whereType<ItemPickup>().single, same(r), reason: 'a drop sent again is not drawn twice');
    await _close(session, [client]);
  });

  test(
    "a client's store is the host's: it shows what the host holds, and a slot it takes is taken everywhere",
    () async {
      final (host, session, [a, b]) = await _session(2, spec: _storeSpec);
      final cell = await _chest(host, [a, b]);
      a.openScreen(StorageScreen(cell));
      b.openScreen(StorageScreen(cell));
      await _settle(() => a.openStorage!.countOf('stone') == 10 && b.openStorage!.countOf('stone') == 10);

      // a takes the stack: its hand holds it at once, and the host settles it.
      a.player.clickSlot(a.openStorage!, 0, one: false);
      expect([a.player.carried!.id, a.player.carried!.count], ['stone', 10]);
      expect(_client(a).pendingStoreEdits, 1);
      await _run([host, a, b], 0.3);
      expect(_client(a).pendingStoreEdits, 0);
      expect(_client(a).storeRefusals, 0);
      expect(host.blockRules.storeAt(cell).countOf('stone'), 0);
      expect(b.openStorage!.countOf('stone'), 0, reason: 'the other screen open on it sees it go');

      // Into a's bag, then half of it back into the store: what left this
      // store in this opening pays for it.
      a.player.clickSlot(a.player.inventory, 3, one: false);
      expect(a.player.carried, isNull);
      a.player.clickSlot(a.player.inventory, 3, one: true);
      final half = a.player.carried!.count;
      a.player.clickSlot(a.openStorage!, 4, one: false);
      await _run([host, a, b], 0.3);
      expect(_client(a).storeRefusals, 0);
      expect(host.blockRules.storeAt(cell).slots[4]!.count, half);
      expect(b.openStorage!.slots[4]!.count, half);
      expect(a.player.inventory.countOf('stone'), 10 - half);

      // The host's own edit reaches both screens.
      host.blockRules.storeAt(cell).add('planks', 7);
      await _run([host, a, b], 0.3);
      expect(a.openStorage!.countOf('planks'), 7);
      expect(b.openStorage!.countOf('planks'), 7);

      // Closed, the store is no longer sent: the host's next edit stays there.
      a.closeScreen();
      await _run([host, a, b], 0.3);
      host.blockRules.storeAt(cell).add('planks', 1);
      await _run([host, a, b], 0.3);
      expect(b.openStorage!.countOf('planks'), 8);
      expect(a.openStorage, isNull);
      await _close(session, [a, b]);
    },
  );

  test(
    'two clients take one stack: the host gives it to the first and the second is refused, its hand emptied',
    () async {
      final (host, session, [a, b]) = await _session(2, spec: _storeSpec);
      final cell = await _chest(host, [a, b]);
      a.openScreen(StorageScreen(cell));
      b.openScreen(StorageScreen(cell));
      await _settle(() => a.openStorage!.countOf('stone') == 10 && b.openStorage!.countOf('stone') == 10);

      a.player.clickSlot(a.openStorage!, 0, one: false);
      b.player.clickSlot(b.openStorage!, 0, one: false);
      expect(a.player.carried?.count, 10);
      expect(b.player.carried?.count, 10);
      await _settle(() => _client(a).pendingStoreEdits == 0 && _client(b).pendingStoreEdits == 0);
      expect(_client(a).storeRefusals + _client(b).storeRefusals, 1);
      final held = [
        for (final c in [a, b]) c.player.carried?.count ?? 0,
      ];
      expect(held..sort(), [0, 10], reason: 'one stack, one hand: the refused take is undone');
      expect(host.blockRules.storeAt(cell).countOf('stone'), 0);
      await _run([host, a, b], 0.3);
      expect(a.openStorage!.countOf('stone'), 0);
      expect(b.openStorage!.countOf('stone'), 0);
      await _close(session, [a, b]);
    },
  );

  test("what a client puts in is paid for: from the hand it declared, never from what it does not hold", () async {
    final (host, session, [a]) = await _session(1, spec: _storeSpec);
    final cell = await _chest(host, [a], stone: 0);
    a.player.pickUp('dirt', 6);
    a.openScreen(StorageScreen(cell));
    await _run([host, a], 0.5);

    // Out of the bag into the hand, declared, then into the store.
    a.player.clickSlot(a.player.inventory, a.player.inventory.find('dirt'), one: false);
    await _run([host, a], 0.5);
    expect(host.remotePlayers.single.carried?.count, 6, reason: 'the hand is declared with the bag');
    a.player.clickSlot(a.openStorage!, 2, one: false);
    await _settle(() => _client(a).pendingStoreEdits == 0);
    expect(_client(a).storeRefusals, 0);
    expect(host.blockRules.storeAt(cell).slots[2]!.count, 6);

    // A hand the client never had: nothing pays for it, so the host refuses
    // it and the hand gets its stack back.
    a.player.carried = ItemStack('planks', 5);
    a.player.clickSlot(a.openStorage!, 1, one: false);
    expect(a.player.carried, isNull);
    await _settle(() => _client(a).pendingStoreEdits == 0);
    expect(_client(a).storeRefusals, 1);
    expect([a.player.carried?.id, a.player.carried?.count], ['planks', 5]);
    expect(host.blockRules.storeAt(cell).slots[1], isNull);
    expect(a.openStorage!.slots[1], isNull, reason: 'the store shows what the host holds');
    expect(a.openStorage!.slots[2]!.count, 6);
    await _close(session, [a]);
  });

  test(
    'a store broken while a client has it open shuts its screen, and one the host has no world for never opens',
    () async {
      final (host, session, [a]) = await _session(1, spec: _storeSpec);
      final cell = await _chest(host, [a]);
      a.openScreen(StorageScreen(cell));
      await _settle(() => a.openStorage!.countOf('stone') == 10);
      host.world.setBlock(cell, BlockRegistry.air);
      await _run([host, a], 0.3);
      expect(a.screen.value, isNull);
      expect(host.entities.whereType<ItemPickup>().single.count, 10, reason: 'it spilled on the host');

      a.player.position = host.player.position + Vector3(300, 0, 0);
      await _run([host, a], 2.0);
      final far = IVec3.floor(a.player.position) + const IVec3(2, 0, 0);
      expect(host.world.isLoaded(far), isFalse);
      a.world.setBlockNamed(far, 'chest');
      a.openScreen(StorageScreen(far));
      await _run([host, a], 0.3);
      expect(a.screen.value, isNull, reason: 'the host keeps no store where it has not loaded the world');
      await _close(session, [a]);
    },
  );

  test(
    "a client follows the host's sky: a storm eases in as the host's does, clears with it, and jumps as it jumps",
    () async {
      final (host, session, [client]) = await _session(1, spec: _skySpec);
      expect(client.weather.kind, WeatherKind.clear);
      host.weather.set(WeatherKind.storm);
      await _run([host, client], 2.0);
      expect(client.weather.spell, WeatherKind.storm);
      expect(host.weather.intensity, closeTo(0.5, 0.05));
      expect(client.weather.intensity, closeTo(host.weather.intensity, 0.05), reason: 'eased, not at once');
      await _run([host, client], 3.0);
      expect(client.weather.kind, WeatherKind.storm);
      expect(client.weather.overcast, closeTo(0.75, 1e-9));

      host.weather.set(WeatherKind.rain, intensity: 0.6);
      await _run([host, client], 5.0);
      expect([client.weather.kind, client.weather.target, client.weather.intensity], [WeatherKind.rain, 0.6, 0.6]);

      host.weather.set(WeatherKind.clear);
      await _run([host, client], 1.0);
      expect(client.weather.spell, WeatherKind.clear);
      expect(client.weather.kind, WeatherKind.rain, reason: 'the rain falls on while it fades out');
      await _run([host, client], 4.0);
      expect(client.weather.kind, WeatherKind.clear);
      expect(client.weather.overcast, 0.0);

      host.weather.set(WeatherKind.storm, now: true);
      await _run([host, client], 0.2);
      expect(client.weather.intensity, 1.0, reason: 'a sky set at once on the host is at once here too');
      await _close(session, [client]);
    },
  );

  test('a client joining a storm has it at once, and strikes on its own clock', () async {
    final host = await VoxelGame.startHeadless(_skySpec);
    host.spawner.enabled = false;
    await _run([host], 1.0);
    host.weather.set(WeatherKind.storm, now: true);
    final session = await host.host(port: 0);
    final client = await VoxelGame.joinGame(_skySpec, '127.0.0.1', port: session.net.port, headless: true);

    // Before the client's first step.
    expect(
      [client.weather.spell, client.weather.kind, client.weather.intensity],
      [WeatherKind.storm, WeatherKind.storm, 1.0],
    );
    expect(client.weather.overcast, closeTo(0.75, 1e-9));
    final hostBolts = <int>[], clientBolts = <int>[];
    for (var i = 0; i < 30 * 60; i++) {
      host.frame(1 / 60);
      client.frame(1 / 60);
      if (host.weather.flash == 1.0) hostBolts.add(i);
      if (client.weather.flash == 1.0) clientBolts.add(i);
      if (i % 30 == 0) await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(clientBolts, isNotEmpty, reason: 'a bolt every 4 to 14 s');
    expect(hostBolts, isNotEmpty);
    expect(clientBolts, isNot(hostBolts), reason: 'each side keeps its own bolt clock');
    await _close(session, [client]);
  });

  test("a client whose player turned the weather off stays clear, and takes the host's sky back on", () async {
    final (host, session, [client]) = await _session(1, spec: _skySpec);
    client.applySettings(client.settings.value.copyWith(weather: false));
    host.weather.set(WeatherKind.rain, intensity: 0.6, now: true);
    await _run([host, client], 1.0);
    expect(client.weather.kind, WeatherKind.clear);
    expect(client.weather.overcast, 0.0);
    client.applySettings(client.settings.value.copyWith(weather: true));
    await _run([host, client], 5.0);
    expect([client.weather.kind, client.weather.intensity], [WeatherKind.rain, 0.6]);
    await _close(session, [client]);
  });

  test(
    "a client tames the host's creature: the host rolls, its puppet owns it, and every side knows the owner",
    () async {
      final (host, session, clients) = await _session(2, spec: _petSpec);
      final [a, b] = clients;
      final puppet = session.players[_client(a).peer]!;
      final wolf = host.spawnMob('wolf', a.player.position + Vector3(0, 0, -2.5));
      await _run([host, ...clients], 0.5);
      final mine = _replicaOf(a, wolf);
      _face(a, mine);
      await _run([host, ...clients], 0.1);
      expect(a.player.aimedMob, same(mine));
      expect(a.player.usableOn(mine), isTrue, reason: "a replica is tamed by asking the host");
      a.input.tap(VoxelAction.use);
      await _run([host, ...clients], 0.5);
      expect(wolf.tamed, isTrue);
      expect(wolf.owner, same(puppet), reason: "the client's puppet owns it on the host");
      expect(a.player.inventory.countOf('bone'), 2, reason: 'one bone went');
      expect(a.notices.feed.last.text, 'The wolf is tamed');
      expect(mine.owner, same(a.player));
      expect(
        _replicaOf(b, wolf).owner,
        same(b.session!.players[_client(a).peer]),
        reason: "the row names the owner's peer",
      );
      expect(a.player.usableOn(mine), isFalse, reason: 'a companion is not ridden');

      a.player.position = a.player.position + Vector3(10, 0, 0);
      await _run([host, ...clients], 4.0);
      expect(wolf.position.distanceTo(puppet.position), lessThan(4.5), reason: 'it heels to its owner, the puppet');
      expect(mine.position.distanceTo(wolf.position), lessThan(0.5));
      await _close(session, clients);
    },
  );

  test(
    'two clients offer to one creature: one tames it, the other has its bone back; a roll that fails spends it',
    () async {
      final (host, session, clients) = await _session(2, spec: _petSpec);
      final [a, b] = clients;
      final wolf = host.spawnMob('wolf', a.player.position + Vector3(0, 0, -2.5));
      await _run([host, ...clients], 0.5);
      for (final c in clients) {
        _face(c, _replicaOf(c, wolf));
      }
      await _run([host, ...clients], 0.1);
      for (final c in clients) {
        c.input.tap(VoxelAction.use);
      }
      await _run([host, ...clients], 0.5);
      final owners = [
        for (final c in clients)
          if (identical(wolf.owner, session.players[_client(c).peer])) c,
      ];
      expect(owners, hasLength(1), reason: 'the first offer the host reads tames it');
      final loser = identical(owners.single, a) ? b : a;
      expect(owners.single.player.inventory.countOf('bone'), 2);
      expect(loser.player.inventory.countOf('bone'), 3, reason: 'an offer to a creature tamed meanwhile comes back');
      expect(
        loser.notices.feed.where((n) => n.text.contains('wolf')),
        isEmpty,
        reason: 'the host rolled nothing for it',
      );

      final shy = host.spawnMob('shy', a.player.position + Vector3(0, 0, 2.5));
      await _run([host, ...clients], 0.5);
      _face(loser, _replicaOf(loser, shy));
      await _run([host, ...clients], 0.1);
      loser.input.tap(VoxelAction.use);
      await _run([host, ...clients], 0.5);
      expect(shy.tamed, isFalse);
      expect(loser.player.inventory.countOf('bone'), 2, reason: 'a taming that does not take still uses up the offer');
      expect(loser.notices.feed.last.text, 'The shy is not won over yet');
      await _close(session, clients);
    },
  );

  test("a client shears the host's creature: the host shears it, and every side sees it shorn", () async {
    final (host, session, clients) = await _session(1, spec: _farmSpec);
    final [a] = clients;
    final sheep = host.spawnMob('sheep', a.player.position + Vector3(0, 0, -2.5));
    await _run([host, ...clients], 0.5);
    final mine = _replicaOf(a, sheep);
    _face(a, mine);
    await _run([host, ...clients], 0.1);
    expect(a.player.usableOn(mine), isTrue, reason: 'a replica is shorn by asking the host');
    a.input.tap(VoxelAction.use);
    await _run([host, ...clients], 0.5);
    expect(sheep.shorn, isTrue);
    expect(mine.shorn, isTrue, reason: "the host's row says so");
    expect(mine.shear, throwsStateError, reason: 'a replica is the host\'s to shear');
    expect(a.player.inventory.slots[a.player.selectedSlot]!.dur, 39, reason: 'the shears wear where they are held');
    expect(a.player.usableOn(mine), isFalse);
    await _close(session, clients);
  });

  test('the night passes once the host and every client sleep, on every side', () async {
    final (host, session, clients) = await _session(1, spec: _farmSpec);
    final [a] = clients;
    Future<void> lieDown(VoxelGame game, IVec3 offset) async {
      final bed = IVec3.floor(game.player.position) + offset;
      host.world.setBlockNamed(bed, 'bed');
      await _run([host, ...clients], 0.3);
      _lookAt(game, Vector3(bed.x + 0.5, bed.y + 0.4, bed.z + 0.5));
      await _run([host, ...clients], 0.1);
      game.input.tap(VoxelAction.use);
      await _run([host, ...clients], 0.1);
      expect(game.player.sleeping, isTrue);
    }

    await lieDown(host, const IVec3(0, 0, -2));
    await _run([host, ...clients], VoxelGame.sleepSeconds + 0.5);
    expect(host.timeOfDay, 0.0, reason: 'the client is awake');
    expect(session.players[_client(a).peer]!.sleeping, isFalse);
    await lieDown(a, const IVec3(2, 0, 0));
    expect(session.players[_client(a).peer]!.sleeping, isTrue, reason: 'its pose says so');
    await _run([host, ...clients], VoxelGame.sleepSeconds + 0.5);
    expect(host.timeOfDay, VoxelGame.morning);
    expect(a.timeOfDay, VoxelGame.morning, reason: "the host's clock is every side's");
    expect(host.player.sleeping, isFalse);
    expect(a.player.sleeping, isFalse, reason: 'up with the morning the host sent');
    await _close(session, clients);
  });

  test("a client rides its own pet: its copy drives, the host's follows, and getting off hands it back", () async {
    final (host, session, clients) = await _session(2, spec: _petSpec);
    final [a, b] = clients;
    final puppet = session.players[_client(a).peer]!;
    final horse = host.spawnMob('horse', a.player.position + Vector3(0, 0, -2.5))..tame(puppet);
    await _run([host, ...clients], 0.5);
    final mine = _replicaOf(a, horse);
    expect(mine.owner, same(a.player));
    expect(host.player.usableOn(horse), isFalse, reason: "the host's player does not ride a client's pet");
    _face(a, mine);
    await _run([host, ...clients], 0.1);
    expect(a.player.usableOn(mine), isTrue);
    a.input.tap(VoxelAction.use);
    await _run([host, ...clients], 0.1);
    expect(a.player.riding, same(mine), reason: 'only its owner rides it, so the client gets on at once');
    expect(mine.rider, same(a.player));

    a.player.yaw = 0.0;
    final from = mine.position.clone();
    a.input.hold(VoxelAction.moveForward, true);
    await _run([host, ...clients], 1.0);
    a.input.hold(VoxelAction.moveForward, false);
    expect(from.z - mine.position.z, greaterThan(3.0), reason: "the client's copy is the live one: no state holds it");
    expect(a.player.position.distanceTo(mine.seat()), lessThan(1e-6));
    await _run([host, ...clients], 0.3);
    expect(horse.rider, same(puppet));
    expect(horse.position.distanceTo(mine.position), lessThan(0.5), reason: "the host's copy follows its rider's");
    final seen = _replicaOf(b, horse);
    expect(seen.rider, same(b.session!.players[_client(a).peer]), reason: "the row names the rider's peer");
    expect(seen.position.distanceTo(mine.position), lessThan(0.6));

    a.input.tap(VoxelAction.sneak);
    await _run([host, ...clients], 0.5);
    expect(a.player.riding, isNull);
    expect(mine.rider, isNull);
    expect(horse.rider, isNull, reason: 'a pose without the mount hands it back to the host');
    expect(mine.position.distanceTo(horse.position), lessThan(0.5), reason: 'the replica follows the host again');
    await _close(session, clients);
  });

  test('a client that leaves gets off, and its pets wait for nobody', () async {
    final (host, session, clients) = await _session(2, spec: _petSpec);
    final [a, b] = clients;
    final puppet = session.players[_client(a).peer]!;
    final horse = host.spawnMob('horse', a.player.position + Vector3(0, 0, -2.5))..tame(puppet);
    final wolf = host.spawnMob('wolf', a.player.position + Vector3(6, 0, 0))..tame(puppet);
    await _run([host, ...clients], 0.5);
    _face(a, _replicaOf(a, horse));
    await _run([host, ...clients], 0.1);
    a.input.tap(VoxelAction.use);
    await _run([host, ...clients], 0.3);
    expect(horse.rider, same(puppet));
    expect(wolf.running.whereType<Heel>(), isNotEmpty);

    await a.session!.close();
    await _run([host, b], 0.5);
    expect(horse.rider, isNull, reason: 'a peer that leaves gets off');
    expect(puppet.isDead, isTrue, reason: 'gone with its peer');
    expect(wolf.running.whereType<Heel>(), isEmpty, reason: 'it heels to nobody');
    final seen = _replicaOf(b, wolf);
    expect(seen.tamed, isTrue, reason: 'a peer gone still owns its pets');
    expect(seen.owner, isNot(same(b.player)));
    await _close(session, [b]);
  });

  test("a client's vehicle is put down by the host: every client draws it, and the hello brings it", () async {
    final (host, session, clients) = await _session(2, spec: _rideSpec);
    final [a, b] = clients;
    final pond = _pond(host);
    await _run([host, ...clients], 0.3);
    final all = [host, ...clients];
    await _standBy(all, a, _over(pond));
    a.player.selectedSlot = a.player.inventory.find('boat');
    a.input.tap(VoxelAction.use);
    await _run(all, 0.05);
    expect(a.vehicles, isEmpty, reason: 'the host puts it down');
    expect(a.player.inventory.countOf('boat'), 1, reason: 'its item spent on the client');
    await _run(all, 0.5);
    final boat = host.vehicles.single;
    expect(IVec3.floor(boat.position).x, pond.x);
    expect(boat.position.y, closeTo(pond.y + 0.9, 0.1), reason: 'on the surface');
    for (final c in clients) {
      final copy = _copyOf(c, boat);
      expect(copy.replica, isTrue);
      expect(copy.position.distanceTo(boat.position), lessThan(0.05));
      expect(copy.facing, closeTo(boat.facing, 1e-9));
    }
    expect(b.player.inventory.countOf('boat'), 2);

    final late = await VoxelGame.joinGame(_rideSpec, '127.0.0.1', port: session.net.port, headless: true);
    expect(_copyOf(late, boat).position.distanceTo(boat.position), lessThan(0.05), reason: 'the hello brings it');
    expect(late.vehicleRows['world'], isEmpty, reason: "a replica is the host's, not the client's to save");
    await _close(session, [...clients, late]);
  });

  test(
    'a client gets on by asking, and drives: the host follows, a second asking is refused, getting off hands it back',
    () async {
      final (host, session, clients) = await _session(2, spec: _rideSpec);
      final [a, b] = clients;
      final all = [host, ...clients];
      final boat = host.placeVehicle('boat', _over(_pond(host)))!;
      await _run(all, 1.0);
      final mine = _copyOf(a, boat), theirs = _copyOf(b, boat);
      await _standBy(all, a, mine.position);
      expect(a.player.aimedVehicle, same(mine));
      a.input.tap(VoxelAction.use);
      a.frame(1 / 60);
      expect(a.player.riding, isNull, reason: 'it asked; the host has not said yet');
      await _run(all, 0.3);
      expect(a.player.riding, same(mine));
      final puppet = session.players[_client(a).peer]!;
      expect(boat.rider, same(puppet));
      expect(theirs.rider, same(b.session!.players[_client(a).peer]), reason: "the row names the rider's peer");
      expect(boat.takes(host.player), isFalse, reason: "the host's player does not take a client's seat");
      b.session!.boardVehicle(theirs);
      await _run(all, 0.3);
      expect(b.player.riding, isNull, reason: 'the seat is taken: the host refuses');
      expect(boat.rider, same(puppet));

      a.player.yaw = 0.0;
      final from = mine.position.clone();
      a.input.hold(VoxelAction.moveForward, true);
      await _run(all, 1.0);
      a.input.hold(VoxelAction.moveForward, false);
      expect(from.z - mine.position.z, greaterThan(3.0), reason: "the client's copy is the live one");
      expect(a.player.position.distanceTo(mine.seat()), lessThan(1e-6));
      await _run(all, 0.3);
      expect(boat.position.distanceTo(mine.position), lessThan(0.5), reason: "the host's copy follows its rider's");
      expect(theirs.position.distanceTo(mine.position), lessThan(1.0), reason: 'two hops behind, still coasting');
      await _run(all, 3.0);
      expect(boat.position.distanceTo(mine.position), lessThan(0.05), reason: 'at rest, where its rider is');
      expect(theirs.position.distanceTo(mine.position), lessThan(0.05));

      a.input.hold(VoxelAction.moveForward, true);
      await _run(all, 0.5);
      a.input.hold(VoxelAction.moveForward, false);
      a.input.tap(VoxelAction.sneak);
      a.frame(1 / 60);
      expect(a.player.riding, isNull);
      final left = mine.position.clone();
      await _settle(() => boat.rider == null);
      expect(boat.position.distanceTo(left), lessThan(1e-3), reason: 'getting off hands it back where it was left');
      await _run(all, 0.3);
      expect(theirs.rider, isNull);
      expect(left.z - boat.position.z, greaterThan(0.3), reason: 'coasting on from there');
      await _run(all, 3.0);
      expect(mine.position.distanceTo(boat.position), lessThan(0.05), reason: 'the replica follows the host again');
      expect(theirs.position.distanceTo(boat.position), lessThan(0.05));
      await _close(session, clients);
    },
  );

  test(
    "a client's swing breaks the host's vehicle nobody rides: gone everywhere, its item dropped; one ridden is not",
    () async {
      final (host, session, clients) = await _session(2, spec: _rideSpec);
      final [a, b] = clients;
      final all = [host, ...clients];
      final pond = _pond(host);
      final ridden = host.placeVehicle('boat', _over(pond) + Vector3(0, 0, 4))!;
      final boat = host.placeVehicle('boat', _over(pond))!;
      host.player.ride(ridden);
      await _run(all, 1.0);
      a.session!.breakVehicle(_copyOf(a, ridden), drop: true);
      await _run(all, 0.3);
      expect(ridden.removed, isFalse, reason: 'the host breaks none that is ridden');

      await _standBy(all, a, _copyOf(a, boat).position);
      expect(a.player.aimedVehicle, same(_copyOf(a, boat)));
      a.input.tap(VoxelAction.attack);
      await _run(all, 0.5);
      expect(boat.removed, isTrue);
      for (final c in clients) {
        expect(c.vehicles.map((v) => v.netId), [ridden.netId], reason: 'gone everywhere');
      }
      expect(host.entities.whereType<ItemPickup>().where((d) => d.stack.id == 'boat'), hasLength(1));
      expect(
        b.entities.whereType<ItemPickup>().where((d) => d.stack.id == 'boat'),
        hasLength(1),
        reason: "the host's drop",
      );
      await _close(session, clients);
    },
  );

  test(
    "a client's minecart: driven along the rails, and left rolling, the host's rolls on as fast from there",
    () async {
      final (host, session, clients) = await _session(1, spec: _rideSpec);
      final [a] = clients;
      final all = [host, a];
      final base = IVec3.floor(host.player.position) + const IVec3(2, 0, 3);
      for (var i = 0; i < 40; i++) {
        host.world.setBlockNamed(base + IVec3(i, 0, 0), 'rail');
      }
      final east = math.atan2(-1.0, 0.0);
      final cart =
          host.placeVehicle('minecart', Vector3(base.x + 2.5, base.y + Minecart.railTop, base.z + 0.5), facing: east)!
              as Minecart;
      await _run(all, 0.5);
      final mine = _copyOf(a, cart) as Minecart;
      a.session!.boardVehicle(mine);
      await _run(all, 0.3);
      expect(a.player.riding, same(mine));
      expect(mine.cell, cart.cell, reason: 'it gets on where the host says it stands');
      a.player.yaw = east;
      a.input.hold(VoxelAction.moveForward, true);
      await _run(all, 1.5);
      a.input.hold(VoxelAction.moveForward, false);
      expect(mine.speed, greaterThan(1.0));
      expect(mine.cell.x - base.x, greaterThan(3), reason: 'pushed east along the line');
      await _run(all, 0.2);
      expect(cart.position.distanceTo(mine.position), lessThan(0.5));

      a.input.tap(VoxelAction.sneak);
      await _run(all, 1 / 60);
      final speed = mine.speed;
      await _run(all, 0.2);
      expect(cart.rider, isNull);
      expect(cart.speed, closeTo(speed, 0.5), reason: "the client's speed comes back in its row");
      final at = cart.position.x;
      await _run(all, 0.5);
      expect(cart.position.x, greaterThan(at + 0.3), reason: 'the host rolls it on');
      await _run(all, 0.3);
      expect(mine.position.distanceTo(cart.position), lessThan(0.3), reason: 'and the client follows it');
      await _close(session, clients);
    },
  );

  test(
    "a client aboard that leaves hands the vehicle back; the host's trip parks it, and its rider gets off",
    () async {
      final (host, session, clients) = await _session(2, spec: _rideSpec);
      final [a, b] = clients;
      final all = [host, ...clients];
      final pond = _pond(host);
      final boat = host.placeVehicle('boat', _over(pond))!;
      final other = host.placeVehicle('boat', _over(pond) + Vector3(0, 0, -6))!;
      await _run(all, 1.0);
      a.session!.boardVehicle(_copyOf(a, boat));
      b.session!.boardVehicle(_copyOf(b, other));
      await _run(all, 0.3);
      expect(boat.rider, same(session.players[_client(a).peer]));
      a.player.yaw = 0.0;
      a.input.hold(VoxelAction.moveForward, true);
      await _run(all, 0.5);
      final left = _copyOf(a, boat).position.clone();
      await a.session!.close();
      await _settle(() => boat.rider == null);
      expect(
        boat.position.distanceTo(left),
        lessThan(0.5),
        reason: 'a peer that leaves gets off, where it last drove it',
      );

      expect(b.player.riding, same(_copyOf(b, other)));
      host.travel('nether');
      await _run([host, b], 0.3);
      expect(b.player.riding, isNull, reason: 'the host parked it: it is gone where the client is');
      expect(b.vehicles, isEmpty);
      expect(host.parkedVehicles['world'], hasLength(2));
      for (var i = 0; i < 600 && host.travelState is Arriving; i++) {
        await _run([host, b], 1 / 60);
      }
      host.travel('world');
      await _run([host, b], 0.5);
      expect(b.vehicles, hasLength(2), reason: 'back with the host');
      await _close(session, [b]);
    },
  );

  test(
    "each player's float is drawn by the others where it floats, its line from their hand, and goes when reeled in",
    () async {
      final (host, session, clients) = await _session(2, spec: _fishSpec);
      final [a, b] = clients;
      final all = [host, ...clients];
      final feet = IVec3.floor(host.player.position);
      _pond(host);
      await _run(all, 0.3);
      await _cast(all, a, IVec3(feet.x + 4, 19, feet.z + 2));
      await _run(all, 1.0);
      final own = a.player.bobber!;
      expect(own.landed, isTrue);
      final puppet = session.players[_client(a).peer]!;
      expect(puppet.float!.distanceTo(own.position), lessThan(0.1), reason: 'the pose carries it');
      final seen = b.session!.players[_client(a).peer]!;
      for (final (game, other) in [(host, puppet), (b, seen)]) {
        final float = other.bobber!;
        expect(float.replica, isTrue);
        expect(float.owner, same(other), reason: 'its line hangs from their hand');
        expect(game.entities, contains(float));
        expect(float.position.distanceTo(own.position), lessThan(0.15));
        expect(() => float.bite(), throwsStateError, reason: "another player's bites are theirs");
      }
      expect(a.entities.whereType<Bobber>().where((f) => f.replica), isEmpty, reason: 'its own is not drawn twice');

      await _cast(all, host, IVec3(feet.x + 4, 19, feet.z - 2));
      await _run(all, 1.0);
      for (final c in clients) {
        final float = c.session!.players[GameSession.hostPeer]!.bobber!;
        expect(float.position.distanceTo(host.player.bobber!.position), lessThan(0.15), reason: "the host's too");
      }

      final drawn = [puppet.bobber!, seen.bobber!];
      a.input.tap(VoxelAction.use);
      await _run(all, 0.3);
      expect(a.player.bobber, isNull, reason: 'reeled in, nothing biting');
      expect(puppet.float, isNull);
      expect([puppet.bobber, seen.bobber], [null, null]);
      expect([for (final f in drawn) f.removed], [true, true]);

      await _cast(all, a, IVec3(feet.x + 4, 19, feet.z + 2));
      await _run(all, 0.3);
      final left = seen.bobber!;
      await a.session!.close();
      await _run([host, b], 0.5);
      expect(left.removed, isTrue, reason: 'a peer that leaves takes its float');
      await _close(session, [b]);
    },
  );

  test("a rider is seen seated, facing the way its seat points, by every other player", () async {
    final (host, session, clients) = await _session(2, spec: _rideSpec);
    final [a, b] = clients;
    final all = [host, ...clients];
    final pond = _pond(host);
    final boat = host.placeVehicle('boat', _over(pond), facing: 0.7)!;
    await _run(all, 1.0);
    final mine = _copyOf(a, boat);
    await _standBy(all, a, mine.position);
    a.input.tap(VoxelAction.use);
    await _run(all, 0.3);
    expect(a.player.riding, same(mine));
    final puppet = session.players[_client(a).peer]!;
    final seen = b.session!.players[_client(a).peer]!;
    expect(puppet.seat, closeTo(mine.facing, 1e-9));
    expect(seen.seat, closeTo(mine.facing, 1e-9));
    await _run(all, 0.5);
    expect(seen.position.distanceTo(mine.seat()), lessThan(0.1), reason: 'where the seat is');

    final own = host.placeVehicle('boat', _over(pond + const IVec3(0, 0, 6)), facing: -1.2)!;
    host.player.ride(own);
    await _run(all, 0.3);
    for (final c in clients) {
      expect(c.session!.players[GameSession.hostPeer]!.seat, closeTo(-1.2, 1e-9), reason: "the host's player too");
    }

    a.input.tap(VoxelAction.sneak);
    await _run(all, 0.3);
    expect(a.player.riding, isNull);
    expect([puppet.seat, seen.seat], [null, null], reason: 'off, it stands');
    await _close(session, clients);
  });

  test(
    "a client's shot is the host's to land, once, and every other player sees it; the host's are seen too",
    () async {
      final (host, session, clients) = await _session(2);
      final [a, b] = clients;
      final all = [host, ...clients];
      // Each its own spot: a shot leaving one player's eye must not start inside another.
      a.player.position = host.player.position + Vector3(5, 0, 0);
      b.player.position = host.player.position + Vector3(0, 0, 8);
      final dummy = host.spawnMob('dummy', a.player.position + Vector3(0, 0, -6));
      await _run(all, 0.5);
      final shot = a.shoot(
        ProjectileSpec.arrow,
        from: a.player.eyePosition,
        at: _replicaOf(a, dummy).centre(),
        owner: a.player,
      );
      expect(shot.replica, isTrue, reason: 'the host lands it');
      await _settle(
        () => host.entities.whereType<Projectile>().isNotEmpty && b.entities.whereType<Projectile>().isNotEmpty,
      );
      final landed = host.entities.whereType<Projectile>().single;
      expect(landed.replica, isFalse);
      expect(landed.owner, same(session.players[_client(a).peer]));
      final seen = b.entities.whereType<Projectile>().single;
      expect(seen.replica, isTrue);
      expect(seen.owner, same(b.session!.players[_client(a).peer]), reason: 'it does not stop on its shooter');
      expect(seen.velocity.distanceTo(shot.velocity), lessThan(1e-9));
      expect(a.entities.whereType<Projectile>(), [shot], reason: 'not sent back to its shooter');
      await _run(all, 1.0);
      expect(dummy.hp, 10 - ProjectileSpec.arrow.damage, reason: "one hit, the host's");
      for (final g in all) {
        expect(g.entities.whereType<Projectile>(), isEmpty, reason: 'each copy stopped on it');
      }

      final hp = a.player.hp;
      host.shoot(ProjectileSpec.arrow, from: host.player.eyePosition, at: a.player.centre(), owner: host.player);
      await _settle(() => a.entities.whereType<Projectile>().isNotEmpty);
      final coming = a.entities.whereType<Projectile>().single;
      expect(coming.replica, isTrue);
      expect(coming.owner, same(a.session!.players[GameSession.hostPeer]));
      await _run(all, 1.0);
      expect(a.player.hp, hp - ProjectileSpec.arrow.damage, reason: "hurt once, by the host's word");
      await _close(session, clients);
    },
  );

  test('an explosive the host lights burns on the client as a replica, and its blast reaches it, heard once', () async {
    final spec = _spec.copyWith(
      blocks: [..._blocks, const BlockType('tnt', color: 0xD03020, hardness: 0)],
      signals: () =>
          const SignalSpec(wire: ('wire', 'wire_lit'), explosives: {'tnt': Explosive(radius: 2.0, fuse: 1.0)}),
    );
    final (host, session, clients) = await _session(1, spec: spec);
    final client = clients.single;
    final cell = IVec3.floor(host.player.position) + const IVec3(10, 0, 0);
    host.world.setBlockNamed(cell, 'tnt');
    await _run([host, client], 0.2);
    expect(() => client.ignite(cell), throwsStateError, reason: 'a client lights nothing');
    host.ignite(cell);
    await _run([host, client], 0.2);
    final replica = client.entities.whereType<LitExplosive>().single;
    expect(replica.replica, isTrue);
    expect(replica.fuse, 1.0);
    expect(replica.position.distanceTo(Vector3(cell.x + 0.5, cell.y.toDouble(), cell.z + 0.5)), lessThan(0.3));
    expect(client.world.blockNameAt(cell), 'air');
    await _run([host, client], 1.0);
    expect(client.entities.whereType<LitExplosive>().where((e) => !e.removed), isEmpty);
    expect(client.world.blockNameAt(cell + IVec3.down), 'air', reason: 'the host\'s crater, as edits');
    final played = (client.sounds as SilentSounds).played;
    expect(played.where((s) => s == 'explode'), hasLength(1), reason: "the host's blast, not the replica's too");

    // A creeper's blast, or any of the host's: heard where it is.
    host.explode(client.player.position + Vector3(0, 0, -6), damage: 0.0, breaksBlocks: false);
    await _settle(() => played.where((s) => s == 'explode').length == 2);
    expect(() => client.explode(client.player.position), throwsStateError, reason: 'a client blows nothing up');
    await _close(session, clients);
  });

  test("a game's own messages: a client's reaches the host's handler, the host's every client or one", () async {
    final heard = <(String, int, Object?)>[];
    MessageHandler on(String type) =>
        (game, from, m) => heard.add((type, from, m['n']));
    final spec = _spec.copyWith(messages: {'wave': on('wave'), 'cheer': on('cheer')});
    final (host, session, clients) = await _session(2, spec: spec);
    final [a, b] = clients;
    final all = [host, a, b];
    final peerA = _client(a).peer, peerB = _client(b).peer;

    a.session!.sendToHost('wave', {'n': 1});
    await _settle(() => heard.isNotEmpty);
    expect(heard.single, ('wave', peerA, 1), reason: "the host's handler, told who sent it");

    heard.clear();
    session.broadcast('cheer', {'n': 2}, except: peerA);
    session.sendTo(peerA, 'wave', {'n': 3});
    await _settle(() => heard.length == 2);
    await _run(all, 0.1);
    expect(heard, hasLength(2), reason: 'never back to the side that sent it');
    expect(heard, containsAll([('cheer', GameSession.hostPeer, 2), ('wave', GameSession.hostPeer, 3)]));

    expect(() => a.session!.sendToHost('dance', {}), throwsArgumentError, reason: 'a type the spec does not declare');
    expect(() => session.broadcast('dance', {}), throwsArgumentError);
    expect(() => session.sendToHost('wave', {}), throwsStateError, reason: 'the host does it itself');
    expect(() => a.session!.broadcast('wave', {}), throwsStateError, reason: 'a client sends to the host');
    expect(() => a.session!.sendTo(peerB, 'wave', {}), throwsStateError);
    await _close(session, clients);
  });

  test(
    'a message no peer of the spec sends throws where it arrives: a type of no one, a game type undeclared',
    () async {
      final (host, session, _) = await _session(0, spec: _spec.copyWith(messages: {'wave': (_, _, _) {}}));
      final errors = <Object>[];
      // A client whose spec has no messages of its own: the host's wave is none it knows.
      final odd = await runZonedGuarded(
        () => VoxelGame.joinGame(_spec, '127.0.0.1', port: session.net.port, headless: true),
        (e, _) => errors.add(e),
      );
      await _run([host, odd!], 1.0);
      expect(errors, isEmpty);
      session.broadcast('wave', {});
      await _settle(() => errors.isNotEmpty);
      session.net.broadcast({'t': 'nonsense'});
      await _settle(() => errors.length == 2);
      expect(errors, everyElement(isA<FormatException>()));
      await _close(session, [odd]);
    },
  );

  test("a pose carries its player's name and its game's extras to every other side", () async {
    final (host, session, clients) = await _session(2);
    final [a, b] = clients;
    final all = [host, a, b];
    final peerA = _client(a).peer;
    await _run(all, 0.2);
    expect(session.players[peerA]!.name, 'Player $peerA', reason: 'a nameless one is its peer');
    expect(b.session!.players[GameSession.hostPeer]!.name, 'Player 1');
    expect(session.players[peerA]!.extras, isEmpty);

    a.player
      ..name = 'Ana'
      ..poseExtras['class'] = 'mage';
    host.player.name = 'Hal';
    await _run(all, 0.3);
    for (final r in [session.players[peerA]!, b.session!.players[peerA]!]) {
      expect(r.name, 'Ana', reason: "the host's puppet and the other client's alike");
      expect(r.extras, {'class': 'mage'});
    }
    expect(a.session!.players[GameSession.hostPeer]!.name, 'Hal');
    expect(() => session.players[peerA]!.extras['class'] = 'thief', throwsUnsupportedError, reason: 'read-only');

    a.player.poseExtras.remove('class');
    await _run(all, 0.3);
    expect(b.session!.players[peerA]!.extras, isEmpty, reason: 'removed, it is no longer sent');
    await _close(session, clients);
  });

  test("a client plays with the options it joins with, and every side draws it as they make it", () async {
    const mageRig = Rig.humanoid(shirt: 0x5A47BF);
    final spec = _spec.copyWith(
      playerFor: () =>
          (player, options) =>
              options['class'] == 'mage' ? player.copyWith(hp: 18.0, rig: mageRig) : player.copyWith(hp: 30.0),
    );
    final host = await VoxelGame.startHeadless(spec, options: const {'class': 'warrior'});
    host.spawner.enabled = false;
    await _run([host], 1.0);
    final session = await host.host(port: 0);
    final a = await VoxelGame.joinGame(
      spec,
      '127.0.0.1',
      port: session.net.port,
      options: const {'class': 'mage'},
      headless: true,
    );
    final b = await VoxelGame.joinGame(spec, '127.0.0.1', port: session.net.port, headless: true);
    final all = [host, a, b];
    await _run(all, 2.0);
    expect(a.options, {'class': 'mage'});
    expect(a.player.spec.hp, 18.0, reason: 'its player is the one its options make');
    expect(a.player.hp, 18.0);
    expect(b.options, isEmpty);
    expect(b.player.spec.hp, 30.0);
    final peerA = _client(a).peer;
    for (final r in [session.players[peerA]!, b.session!.players[peerA]!]) {
      expect(r.options, {'class': 'mage'}, reason: "the host's puppet and the other client's alike");
      expect(spec.playerWith(r.options).rig, same(mageRig));
    }
    expect(a.session!.players[GameSession.hostPeer]!.options, {'class': 'warrior'});
    expect(session.players[_client(b).peer]!.options, isEmpty);
    expect(() => a.options['class'] = 'rogue', throwsUnsupportedError);
    expect(
      () => VoxelGame.startHeadless(
        spec,
        info: const WorldInfo(slot: 's', name: 'S', seed: 1, saved: false),
        options: const {'class': 'mage'},
      ),
      throwsArgumentError,
      reason: "a world's options are its info's",
    );
    await _close(session, [a, b]);
  });

  test("a client generates the world its host's options make", () async {
    const plaza = Plaza(minX: -8, minZ: -8, maxX: 8, maxZ: 8, height: 26, biome: 'plains');
    final spec = _spec.copyWith(
      worldFor: () =>
          (world, options) => options['kind'] == 'showroom' ? world.withPlaza(plaza) : world,
    );
    final host = await VoxelGame.startHeadless(
      spec.copyWith(world: spec.worldWith(const {'kind': 'showroom'})),
      options: const {'kind': 'showroom'},
    );
    host.spawner.enabled = false;
    await _run([host], 1.0);
    final session = await host.host(port: 0);
    final client = await VoxelGame.joinGame(spec, '127.0.0.1', port: session.net.port, headless: true);
    await _run([host, client], 1.0);
    expect(host.world.generator.surfaceHeight(0, 0), 26);
    expect(client.world.generator.surfaceHeight(0, 0), 26, reason: "the host's plaza, not the declared flat");
    expect(client.world.generator.surfaceHeight(40, 0), 20);
    expect(client.options, isEmpty, reason: "the host's options shape the world, not the client's game");
    await _close(session, [client]);
  });

  test("a hurt the host deals a client's player leaves its effect there, and says what hurt it", () async {
    final spec = _spec.copyWith(
      effects: const [EffectType('poison', 'Poison', 0.3, 0.6, 0.2, period: 1.0, damage: 1.0, bad: true)],
      mobs: [
        ..._spec.mobs,
        const MobSpec('spider', hp: 10, brain: [], onHit: HitEffect('poison', seconds: 8.0)),
      ],
    );
    final (host, session, clients) = await _session(1, spec: spec);
    final client = clients.single;
    final puppet = session.players[_client(client).peer]!;
    final sources = <String>[];
    client.player.damageIn['seen'] = (d, amount) {
      sources.add(d.source);
      return amount;
    };
    final spider = host.spawnMob('spider', host.player.position + Vector3(0, 0, -4));
    final hp = client.player.hp;
    spider.strike(puppet, Damage(2, from: spider.position, attacker: spider));
    await _settle(() => client.player.effects.has('poison'));
    expect(client.player.hp, lessThan(hp));
    expect(sources, ['melee']);
    expect(host.player.effects.has('poison'), isFalse, reason: "worn on the peer's side");

    await _run([host, client], 0.5); // past the blow's grace
    client.player.effects.clear('poison');
    client.player.damageIn['dodge'] = (d, amount) => 0.0;
    puppet.takeDamage(const Damage(2, source: 'explosion', effect: HitEffect('poison')));
    await _settle(() => sources.length == 2);
    await _run([host, client], 0.1);
    expect(sources.last, 'explosion');
    expect(client.player.effects.has('poison'), isFalse, reason: 'a hurt that never lands leaves nothing');
    await _close(session, clients);
  });

  test("a client's shot the host lands on a creature is dealt by the client's own filters", () async {
    final (host, session, clients) = await _session(1);
    final a = clients.single;
    a.player.position = host.player.position + Vector3(5, 0, 0);
    final dummy = host.spawnMob('dummy', a.player.position + Vector3(0, 0, -6));
    await _run([host, a], 0.5);
    a.player.damageOut['half'] = (mob, amount) => amount / 2;
    host.player.damageOut['none'] = (mob, amount) => 0.0;
    a.shoot(ProjectileSpec.arrow, from: a.player.eyePosition, at: _replicaOf(a, dummy).centre(), owner: a.player);
    await _run([host, a], 1.0);
    expect(dummy.hp, 10 - ProjectileSpec.arrow.damage / 2, reason: "the shooter's filter, not the host's");
    expect(dummy.lastHurtBy, same(session.players[_client(a).peer]));
    await _close(session, clients);
  });

  test("a client stuns, slows and calms the host's creature through the host", () async {
    final (host, session, clients) = await _session(1);
    final a = clients.single;
    final biter = host.spawnMob('biter', a.player.position + Vector3(0, 0, -8));
    await _run([host, a], 0.5);
    expect(biter.target, isNotNull, reason: 'it hunts');
    final replica = _replicaOf(a, biter);
    replica
      ..stun(2.0)
      ..slow(0.5, 3.0);
    await _settle(() => biter.stunned && biter.pace == 0.5);
    replica.forget();
    await _settle(() => biter.target == null);
    expect(replica.stunned, isFalse, reason: "the replica is only the host's word");
    await _close(session, clients);
  });
}
