import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';

/// Anything that lives in the world and moves each step: a mob, a dropped
/// item, a projectile. A [NodeBody] (a voxel body with a scene node), ticked
/// by its [VoxelGame]; set `removed` and the game drops it after the step.
abstract class GameEntity extends NodeBody {
  /// Advances this entity by one step of [dt] seconds.
  void tick(VoxelGame game, double dt);

  /// Called once when the game adds it: build visuals here (never headless).
  void attached(VoxelGame game) {}
}

/// A system the game runs every step after its own (spawning, weather, a
/// quest tracker): the Bonfire-style hook for game logic without subclassing.
abstract interface class GameSystem {
  /// Advances by one step of [dt] seconds.
  void tick(VoxelGame game, double dt);
}
