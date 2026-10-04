import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

/// What the player did in this world, counted: the time played, the metres
/// walked, blocks broken and placed, creatures killed, deaths, trips through
/// a portal and things crafted. The stats screen shows them, and the
/// achievements read them (`Achievements`).
///
/// Saved with the world (under `stats`).
class GameStats extends SavedSystem {
  /// The key of its counts in the save.
  static const String key = 'stats';

  /// Metres one step may carry the player and still be a walk: past it the
  /// player was carried off (a respawn, a trip), not walking.
  static const double longestStride = 1.0;

  /// The stats of [game].
  static GameStats of(VoxelGame game) => game.system<GameStats>();

  /// Seconds played in this world.
  double playTime = 0.0;

  /// Metres walked on the ground.
  double walked = 0.0;

  /// Blocks the player broke.
  int blocksBroken = 0;

  /// Blocks the player placed.
  int blocksPlaced = 0;

  /// Creatures the player killed.
  int kills = 0;

  /// Times the player died.
  int deaths = 0;

  /// Trips through a portal.
  int trips = 0;

  /// Recipes crafted, once a craft.
  int crafted = 0;

  Vector3? _last;

  @override
  void tick(VoxelGame game, double dt) {
    playTime += dt;
    final p = game.player;
    final at = Vector3(p.position.x, 0.0, p.position.z);
    final last = _last;
    _last = at;
    if (last == null || p.isDead || !p.onFloor || p.riding != null) return;
    final stride = at.distanceTo(last);
    if (stride <= longestStride) walked += stride;
  }

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    switch (event) {
      case BlockBroken():
        blocksBroken += 1;
      case BlockPlaced():
        blocksPlaced += 1;
      case MobKilled(byPlayer: true):
        kills += 1;
      case PlayerDied():
        deaths += 1;
      case Travelled(through: PortalSpec()):
        trips += 1;
      case ItemCrafted():
        crafted += 1;
      default:
    }
  }

  /// [seconds] as the stats screen shows a time: `1h 02m`, or `4m 05s`
  /// under an hour.
  static String timeLabel(double seconds) {
    final s = seconds.floor();
    String two(int n) => n.toString().padLeft(2, '0');
    if (s >= 3600) return '${s ~/ 3600}h ${two(s % 3600 ~/ 60)}m';
    return '${s ~/ 60}m ${two(s % 60)}s';
  }

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {
    'play_time': playTime,
    'walked': walked,
    'blocks_broken': blocksBroken,
    'blocks_placed': blocksPlaced,
    'kills': kills,
    'deaths': deaths,
    'trips': trips,
    'crafted': crafted,
  };

  @override
  void restore(VoxelGame game, Object? saved) {
    final row = saved! as Map<String, Object?>;
    playTime = (row['play_time']! as num).toDouble();
    walked = (row['walked']! as num).toDouble();
    blocksBroken = row['blocks_broken']! as int;
    blocksPlaced = row['blocks_placed']! as int;
    kills = row['kills']! as int;
    deaths = row['deaths']! as int;
    trips = row['trips']! as int;
    crafted = row['crafted']! as int;
  }
}
