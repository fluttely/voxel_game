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
}
