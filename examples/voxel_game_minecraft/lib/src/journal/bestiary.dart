import 'package:voxel_game/voxel_game.dart';

import '../spec/mob_table.dart';

/// The creatures the player has met and how many of each they killed, by
/// kind (`plainKinds`: an elite counts as the creature it twists). A
/// creature is met once it is in the loaded world beside the player. The
/// journal's Bestiary lists [kinds], the ones not met yet as `???`.
///
/// Saved with the world (under `bestiary`).
class Bestiary extends SavedSystem {
  /// The key of what it knows in the save.
  static const String key = 'bestiary';

  /// Seconds between two looks at the creatures around.
  static const double lookEvery = 1.0;

  /// The creatures it lists, in the table's order: every species but the
  /// people one trades with.
  static final List<MobSpec> kinds = [
    for (final s in speciesTable)
      if (!_people.contains(s.id)) s,
  ];

  // The villager trades (VA-Zl); the bestiary is of what one fights or tames.
  static const Set<String> _people = {'villager'};

  /// The bestiary of [game].
  static Bestiary of(VoxelGame game) => game.system<Bestiary>();

  /// Kills by kind.
  final Map<String, int> kills = {};

  /// The kinds met.
  final Set<String> seen = {};

  double _lookIn = 0.0;

  /// The kills of the kind [id].
  int killsOf(String id) => kills[id] ?? 0;

  /// Whether the kind [id] was met (or killed).
  bool met(String id) => seen.contains(id);

  @override
  void tick(VoxelGame game, double dt) {
    _lookIn -= dt;
    if (_lookIn > 0.0) return;
    _lookIn = lookEvery;
    for (final m in game.mobs) {
      seen.add(plainKinds[m.spec.id]!);
    }
  }

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    if (event case MobKilled(:final mob, byPlayer: true)) {
      final kind = plainKinds[mob.spec.id]!;
      seen.add(kind);
      kills[kind] = killsOf(kind) + 1;
    }
  }

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {'kills': kills, 'seen': seen.toList()..sort()};

  @override
  void restore(VoxelGame game, Object? saved) {
    final row = saved! as Map<String, Object?>;
    kills
      ..clear()
      ..addAll((row['kills']! as Map<String, Object?>).map((id, n) => MapEntry(id, n! as int)));
    seen
      ..clear()
      ..addAll((row['seen']! as List<Object?>).cast<String>());
    for (final id in [...kills.keys, ...seen]) {
      if (!plainKinds.containsKey(id)) throw FormatException('the bestiary knows no $id');
    }
  }
}
