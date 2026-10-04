import 'dart:math' as math;

import 'package:voxel_game/voxel_game.dart';

import '../spec/mob_table.dart';
import 'quest.dart';
import 'quest_chain.dart';

/// Where the player is in the [questChain]: one quest at a time, counted
/// off the events (a pickup, a craft, a kill) or read off the player (a
/// level, what the bag carries). A quest done gives its experience and its
/// items (what the bag cannot hold falls at the player's feet) and the next
/// one starts from nothing; what was counted past the goal is not carried.
///
/// Saved with the world (under `quests`).
class QuestLog extends SavedSystem {
  /// The key of where the chain is in the save.
  static const String key = 'quests';

  /// The quest log of [game].
  static QuestLog of(VoxelGame game) => game.system<QuestLog>();

  /// How many quests of the chain are done.
  int index = 0;

  /// What is counted toward the quest at hand (a pickup, a craft, a kill).
  int counted = 0;

  /// The quest at hand, or null with the chain done.
  Quest? get current => index < questChain.length ? questChain[index] : null;

  /// How far the quest at hand is, out of its `Quest.count`: what was
  /// counted, or for a level or a carry what the player has now.
  int progressOf(VoxelGame game) {
    final q = current;
    if (q == null) return 0;
    final p = game.player;
    return math.min(switch (q.goal) {
      QuestGoal.collect || QuestGoal.craft || QuestGoal.kill => counted,
      QuestGoal.level => p.level,
      QuestGoal.have => q.targets.map(p.inventory.countOf).reduce(math.max),
    }, q.count);
  }

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    final q = current;
    if (q == null) return;
    final n = switch ((q.goal, event)) {
      (QuestGoal.collect, ItemPickedUp(:final item, :final count)) when q.targets.contains(item) => count,
      (QuestGoal.craft, ItemCrafted(:final recipe)) when q.targets.contains(recipe.result) => recipe.count,
      (QuestGoal.kill, MobKilled(:final mob, byPlayer: true)) when q.targets.contains(plainKinds[mob.spec.id]) => 1,
      _ => 0,
    };
    if (n == 0) return;
    counted += n;
    if (counted >= q.count) _complete(game, q);
  }

  @override
  void tick(VoxelGame game, double dt) {
    final q = current;
    if (q == null || game.player.isDead) return;
    if ((q.goal == QuestGoal.level || q.goal == QuestGoal.have) && progressOf(game) >= q.count) _complete(game, q);
  }

  void _complete(VoxelGame game, Quest q) {
    final p = game.player;
    game.notify('Quest complete: ${q.title}!');
    game.playSound('quest');
    p.gainXp(q.xp);
    for (final MapEntry(key: item, value: count) in q.items.entries) {
      final left = p.inventory.add(item, count);
      if (left > 0) game.dropItem(item, left, p.position);
    }
    index += 1;
    counted = 0;
    final next = current;
    if (next != null) game.notify('New quest: ${next.title}');
  }

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {'index': index, 'counted': counted};

  @override
  void restore(VoxelGame game, Object? saved) {
    final row = saved! as Map<String, Object?>;
    index = row['index']! as int;
    counted = row['counted']! as int;
    if (index < 0 || index > questChain.length || counted < 0) throw FormatException('no such quest: $row');
  }
}
