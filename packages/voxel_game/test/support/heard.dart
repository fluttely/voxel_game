import 'package:voxel_game/voxel_game.dart';

/// A system that writes down every event it hears: a test's ear on a game.
class Heard extends GameSystem {
  /// What it heard, in order.
  final List<GameEvent> events = [];

  @override
  void onEvent(VoxelGame game, GameEvent event) => events.add(event);
}
