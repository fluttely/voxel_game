import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _spec = VoxelGameSpec(
  blocks: [
    BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
    BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType.liquid('water', color: 0x3366CC),
    BlockType.liquid('water_flow', color: 0x3366CC, kind: 'water', source: false),
  ],
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  seed: 7,
  sky: SkySpec.alwaysDay,
);

const _lobby = SpawnPoint(x: 40, z: -24, yaw: 1.25);

/// A game whose showroom starts at [_lobby], and every other world where the
/// kit finds one.
final VoxelGameSpec _showroom = _spec.copyWith(
  spawn: () =>
      (options) => options['kind'] == 'showroom' ? _lobby : null,
);

/// Steps [game] until the player stands in the world; [each] looks at it
/// before every frame.
Future<void> _settle(VoxelGame game, {void Function()? each}) async {
  for (var i = 0; i < 600 && !game.ready; i++) {
    each?.call();
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
}

void main() {
  test('a declared spawn stands a new world\'s player there, facing its yaw, from before the first frame', () async {
    final game = await VoxelGame.startHeadless(_showroom, options: const {'kind': 'showroom'});
    game.spawner.enabled = false;
    void atLobby() {
      expect(game.player.position.x, 40.5);
      expect(game.player.position.z, -23.5);
      expect(game.player.yaw, 1.25);
    }

    atLobby();
    await _settle(game, each: atLobby);
    atLobby();
    expect(game.player.position.y, closeTo(20.0, 0.05), reason: 'on the ground of the column');
    expect(game.player.spawnPoint, game.player.position, reason: 'the respawn point');
  });

  test('a null spawn, or none answered, keeps the kit\'s dry column by the origin', () async {
    for (final (spec, options) in [
      (_spec, const {'kind': 'showroom'}),
      (_showroom, const {'kind': 'open'}),
    ]) {
      final game = await VoxelGame.startHeadless(spec, options: options);
      game.spawner.enabled = false;
      await _settle(game);
      expect(game.player.position.x, 0.5, reason: '$options');
      expect(game.player.position.z, 0.5, reason: '$options');
      expect(game.player.yaw, 0.0, reason: '$options');
    }
  });

  test('a world\'s options choose the spawn; a reloaded world keeps the place it was saved at', () async {
    final dir = Directory.systemTemp.createTempSync('voxel_spawn');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final w = saves.create('Lobby', seed: 7, options: const {'kind': 'showroom'});
    final game = await VoxelGame.startHeadless(saves.info(w.slot).applyTo(_showroom), info: saves.info(w.slot));
    game.spawner.enabled = false;
    await _settle(game);
    expect(game.player.position.x, 40.5);
    game.player
      ..placeAt(Vector3(3.5, 20.0, 9.5))
      ..yaw = -0.5;
    saves.save(game, w.slot);

    final info = saves.info(w.slot);
    final back = await VoxelGame.startHeadless(info.applyTo(_showroom), info: info, save: saves.read(w.slot));
    back.spawner.enabled = false;
    await _settle(back);
    expect(back.player.position.x, 3.5);
    expect(back.player.position.z, 9.5);
    expect(back.player.yaw, -0.5);
    expect(back.player.spawnPoint.x, 40.5, reason: 'the respawn point the new world had');
  });
}
