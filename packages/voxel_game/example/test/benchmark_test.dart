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
}
