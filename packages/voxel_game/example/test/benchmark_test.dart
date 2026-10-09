import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_example/benchmark.dart';
import 'package:voxel_game_example/main.dart' as example;

/// The spec `lib/benchmark.dart` runs, made into a game with no screen and no
/// GPU: the game's constructor runs every check `VoxelGame.start` does, so a
/// spec the kit refuses fails here and not at the owner's next benchmark
/// (KL-030). Nothing here measures a frame.
void main() {
  final runs = {
    for (final s in Scenario.values) s.name: ['--scenario=${s.name}'],
    'phone graphics': ['--graphics=phone', '--shadows=off', '--aa=none'],
    'peers, edits and aim': ['--peers=2', '--edits=64', '--aim'],
  };
  for (final MapEntry(key: name, value: args) in runs.entries) {
    test('the $name run makes a game', () async {
      final bench = Bench.parse(['--radius=2', ...args]);
      final game = await VoxelGame.startHeadless(bench.spec, loadRadius: 2);
      addTearDown(game.dispose);
      expect(game.player.spec.creative, isTrue, reason: 'the hunters of the mobs run cannot end it');
      expect(
        game.systems.length,
        example.game.systems().length + 1,
        reason: "the bench's driver runs after the game's",
      );
    });
  }

  test("the cave run's eye is in a cave the sky does not reach", () async {
    final bench = Bench.parse(['--scenario=cave', '--radius=2']);
    final game = await VoxelGame.startHeadless(bench.spec, loadRadius: 2);
    addTearDown(game.dispose);
    game.spawner.enabled = false;
    for (var i = 0; i < 600 && !game.ready; i++) {
      game.frame(1 / 60);
      await Future<void>.delayed(Duration.zero);
    }
    expect(game.ready, isTrue);
    // The eye's open cells, flooded as the mesher's connectivity floods them
    // (a headless world bakes no light to read the sky's from): air that
    // reaches over the ground joins the open sky, from which the view hides
    // nothing, and the run would measure what orbit does.
    final world = game.world, opaque = game.blocks.table.isOpaque;
    expect(opaque(world.getBlock(Bench.caveEye)), isFalse, reason: 'a world that moved puts the eye in stone');
    final seen = {Bench.caveEye}, queue = [Bench.caveEye];
    while (queue.isNotEmpty) {
      final c = queue.removeLast();
      expect(world.isLoaded(c), isTrue, reason: 'the cave runs out of the loaded window at $c');
      expect(c.y, lessThan(world.groundHeight(c.x, c.z)), reason: 'the cave opens to the sky at $c');
      for (final n in [
        IVec3(c.x - 1, c.y, c.z),
        IVec3(c.x + 1, c.y, c.z),
        IVec3(c.x, c.y - 1, c.z),
        IVec3(c.x, c.y + 1, c.z),
        IVec3(c.x, c.y, c.z - 1),
        IVec3(c.x, c.y, c.z + 1),
      ]) {
        if (!opaque(world.getBlock(n)) && seen.add(n)) queue.add(n);
      }
    }
  });
}
