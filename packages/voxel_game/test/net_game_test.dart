import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
  BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
  BlockType('planks', color: 0xB08850, hardness: 1.0, tool: 'axe'),
  BlockType.liquid('water', color: 0x3366CC),
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

void main() {
  test('a client joins a host: the world, edits both ways, players, mobs, hits and hurts', () async {
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
    replica.takeDamage(Damage(4, from: client.player.position, attacker: client.player));
    await _run([host, client], 0.3);
    expect(dummy.hp, 6);
    expect(replica.hp, 6, reason: "the host's health comes back");

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
}
