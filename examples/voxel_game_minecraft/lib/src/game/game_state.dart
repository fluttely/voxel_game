import 'achievements.dart';

/// Session-wide settings and statistics (persisted with the save).
class GameState {
  GameState._();
  static final GameState instance = GameState._();

  int seedValue = 1337;
  String playerClass = 'warrior';
  String worldName = 'default';
  bool freshWorld = false;
  int blocksMined = 0;
  int blocksPlaced = 0;
  int mobsKilled = 0;
  int deaths = 0;
  double playTime = 0.0; // seconds of play in this world (the stats block's play time)
  bool creative = false; // stage 30: no damage, no hunger, free blocks, fly allowed
  bool playground = false; // stage 33: the showcase world (flat plaza, exhibits, F7-F9)
  double distanceWalked = 0.0; // stage 30: metres on the ground, saved with the stats
  int dimensionVisits = 0; // stage 30: portal trips taken
  final Set<String> placedChests = {};

  /// Bestiary: kills per species, and every species ever met.
  final Map<String, int> kills = {};
  final Set<String> seen = {};

  Map<String, Object> toJson() => {
        'blocks_mined': blocksMined,
        'blocks_placed': blocksPlaced,
        'mobs_killed': mobsKilled,
        'deaths': deaths,
        'play_time': playTime,
        'class': playerClass,
        'creative': creative,
        'playground': playground,
        'distance_walked': distanceWalked,
        'dimension_visits': dimensionVisits,
        'placed_chests': placedChests.toList(),
        'kills': kills,
        'seen': seen.toList(),
        'achievements': Achievements.instance.toJson(),
      };

  void fromJson(Map<String, dynamic> d) {
    blocksMined = (d['blocks_mined'] as num?)?.toInt() ?? 0;
    blocksPlaced = (d['blocks_placed'] as num?)?.toInt() ?? 0;
    mobsKilled = (d['mobs_killed'] as num?)?.toInt() ?? 0;
    deaths = (d['deaths'] as num?)?.toInt() ?? 0;
    playTime = (d['play_time'] as num?)?.toDouble() ?? 0.0;
    creative = d['creative'] == true;
    playground = d['playground'] == true;
    distanceWalked = (d['distance_walked'] as num?)?.toDouble() ?? 0.0;
    dimensionVisits = (d['dimension_visits'] as num?)?.toInt() ?? 0;
    playerClass = d['class']?.toString() ?? playerClass;
    placedChests.clear();
    for (final k in (d['placed_chests'] as List<dynamic>? ?? const [])) {
      placedChests.add(k.toString());
    }
    kills.clear();
    for (final e in (d['kills'] as Map<String, dynamic>? ?? const {}).entries) {
      kills[e.key] = (e.value as num).toInt();
    }
    seen.clear();
    for (final k in (d['seen'] as List<dynamic>? ?? const [])) {
      seen.add(k.toString());
    }
    Achievements.instance.fromJson(d['achievements'] as Map<String, dynamic>? ?? const {});
  }

  /// Stage 30: a world started from the title begins with zeroed counters
  /// (see `Worlds.start`); the class is kept, the mode goes back to survival.
  void resetStats() => fromJson(const {});
}
