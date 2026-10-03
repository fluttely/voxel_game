import 'voxel_game.dart';
import 'game_event.dart';

/// A game's own logic, run by its [VoxelGame] (spawning, a quest tracker, a
/// class's cooldowns): the Bonfire-style hook for game logic without
/// subclassing. A game declares its systems as `VoxelGameSpec.systems`, a
/// factory called once for each game made, so a second world never shares the
/// first one's state; `VoxelGame.systems` holds them, `VoxelGame.system`
/// finds one by its type.
///
/// Each step, after the game's own, every event raised since the systems
/// last heard is handed to each of them, in the order they happened
/// ([onEvent]), then every system is [tick]ed, in the order the spec lists
/// them. Override either or both.
abstract mixin class GameSystem {
  /// Advances by one step of [dt] seconds.
  void tick(VoxelGame game, double dt) {}

  /// Hears [event]: something the player did or that happened to them.
  void onEvent(VoxelGame game, GameEvent event) {}
}

/// A [GameSystem] whose state is the world's: written into the world's save
/// under [saveKey] (in `game.json`'s `game`, `WorldSaves`) and put back when
/// the world loads. A world never saved with it (new, or saved before the
/// game had it) never calls [restore]: the system starts as made.
abstract class SavedSystem extends GameSystem {
  /// Its key in the save: one system's alone (`VoxelGame` throws for two).
  String get saveKey;

  /// Its state as JSON (maps of strings, lists, strings, numbers, booleans,
  /// null), as [restore] will read it back.
  Object? save(VoxelGame game);

  /// Puts back what [save] wrote, once, as the world loads: after the
  /// player, the world's clock and its creatures are back, before the first
  /// step. A load raises no event.
  void restore(VoxelGame game, Object? saved);
}
