import 'package:voxel_game/voxel_game.dart';

import 'achievement_table.dart';

/// The achievements unlocked in this world ([achievementTable]): each by its
/// event or its state, or by [unlock] from another system; told once, with
/// a chime.
///
/// Saved with the world (under `achievements`).
class Achievements extends SavedSystem {
  /// The key of what is unlocked in the save.
  static const String key = 'achievements';

  /// The achievements of [game].
  static Achievements of(VoxelGame game) => game.system<Achievements>();

  /// The ids unlocked.
  final Set<String> unlocked = {};

  /// Whether [id] is unlocked.
  bool has(String id) => unlocked.contains(id);

  /// Unlocks [id], told the first time; throws for an id the table lacks.
  void unlock(VoxelGame game, String id) {
    final a = achievementById(id);
    if (!unlocked.add(id)) return;
    game.notify('Achievement: ${a.name}');
    game.playSound('quest', volumeDb: -4.0);
  }

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    for (final a in achievementTable) {
      final on = a.on;
      if (on != null && !has(a.id) && on(game, event)) unlock(game, a.id);
    }
  }

  @override
  void tick(VoxelGame game, double dt) {
    for (final a in achievementTable) {
      final state = a.when;
      if (state != null && !has(a.id) && state(game)) unlock(game, a.id);
    }
  }

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {'unlocked': unlocked.toList()..sort()};

  @override
  void restore(VoxelGame game, Object? saved) {
    final ids = ((saved! as Map<String, Object?>)['unlocked']! as List<Object?>).cast<String>();
    for (final id in ids) {
      achievementById(id);
    }
    unlocked
      ..clear()
      ..addAll(ids);
  }
}
