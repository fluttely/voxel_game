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
}
