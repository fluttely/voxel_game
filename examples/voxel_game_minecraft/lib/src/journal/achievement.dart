import 'package:voxel_game/voxel_game.dart';

/// Whether [event] unlocks an achievement in [game].
typedef AchievementEvent = bool Function(VoxelGame game, GameEvent event);

/// Whether [game]'s state unlocks an achievement.
typedef AchievementState = bool Function(VoxelGame game);

/// An achievement: unlocked once, by an event ([on]) or by a state checked
/// every step ([when]). One with neither is unlocked by a system of the
/// game's own when its thing happens (`Achievements.unlock`: a waypoint's
/// trip, a fortress found).
class Achievement {
  /// The achievement [id], shown as [name] with its [description].
  const Achievement(this.id, this.name, this.description, {this.on, this.when})
    : assert(on == null || when == null, 'an event or a state, not both');

  /// Its key in the save.
  final String id;

  /// What the journal and the toast call it.
  final String name;

  /// What unlocks it, in a line.
  final String description;

  /// The event that unlocks it, or null.
  final AchievementEvent? on;

  /// The state that unlocks it, or null.
  final AchievementState? when;
}
