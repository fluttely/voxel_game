import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

import '../classes/class_system.dart';
import '../journal/achievements.dart';

/// A waypoint the player placed: its [cell], the [dimension] it stands in,
/// and its [label] (`Waypoint 3`).
typedef Waypoint = ({IVec3 cell, String dimension, String label});

/// The waypoints of this world: each one placed is named and listed (the
/// journal's Waypoints tab, J or a waypoint used); one broken, or found gone
/// where it stood, is forgotten. The player travels to one of the dimension
/// they are in ([travel]): free beside another waypoint ([nearby] metres),
/// [cost] mana from afar.
///
/// Saved with the world (under `waypoints`).
class Waypoints extends SavedSystem {
  /// The key of the waypoints in the save.
  static const String key = 'waypoints';

  /// The block that is a waypoint.
  static const String block = 'waypoint';

  /// The screen a waypoint opens: the journal on its Waypoints tab.
  static const String screen = 'waypoints';

  /// Metres from a waypoint within which a trip is free.
  static const double nearby = 6.0;

  /// The mana a trip from afar costs.
  static const double cost = 10.0;

  /// Seconds between two looks at the waypoints loaded, for one gone.
  static const double lookEvery = 1.0;

  /// The waypoints of [game].
  static Waypoints of(VoxelGame game) => game.system<Waypoints>();

  /// Opens the waypoints of [game]: the use of a waypoint block.
  static void open(VoxelGame game, IVec3 cell) => game.openScreen(const DeclaredScreen(screen));

  final List<Waypoint> _all = [];
  ({Vector3 at, IVec3 cell})? _arriving;
  double _lookIn = 0.0;

  /// Every waypoint, by label.
  List<Waypoint> get all => [..._all]..sort((a, b) => a.label.compareTo(b.label));

  /// Where a trip to [w] stands the player: on top of it.
  static Vector3 landingOf(Waypoint w) => Vector3(w.cell.x + 0.5, w.cell.y + 1.05, w.cell.z + 0.5);

  /// Travels the player of [game] to [w]: false, and nothing spent, when [w]
  /// is in another dimension or the player is short of mana. A waypoint not
  /// loaded yet holds the player above it until it is.
  bool travel(VoxelGame game, Waypoint w) {
    if (w.dimension != game.dimension) {
      game.notify('${w.label} is in another world');
      return false;
    }
    final p = game.player;
    final free = _all.any((o) => o.dimension == game.dimension && _centre(o.cell).distanceTo(p.position) <= nearby);
    if (!free) {
      final classes = ClassSystem.of(game);
      if (classes.mana < cost) {
        game.notify('Need ${cost.round()} mana to travel from afar');
        return false;
      }
      classes.mana -= cost;
    }
    final at = landingOf(w);
    if (game.world.isLoaded(w.cell)) {
      p.placeAt(at);
    } else {
      p.hold(at);
      _arriving = (at: at, cell: w.cell);
    }
    game.playSound('quest', volumeDb: -6.0);
    game.notify('Travelled to ${w.label}');
    Achievements.of(game).unlock(game, 'traveler');
    return true;
  }

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    switch (event) {
      case BlockPlaced(block: Waypoints.block, :final cell):
        final label = _nextLabel();
        _all.add((cell: cell, dimension: game.dimension, label: label));
        game.notify('$label set. Use it to travel (J lists them)');
      case BlockBroken(block: Waypoints.block, :final cell):
        _forget(game.dimension, cell);
      default:
    }
  }

  @override
  void tick(VoxelGame game, double dt) {
    final arriving = _arriving;
    if (arriving != null && game.world.isLoaded(arriving.cell)) {
      game.player.placeAt(arriving.at);
      _arriving = null;
    }
    _lookIn -= dt;
    if (_lookIn > 0.0) return;
    _lookIn = lookEvery;
    // A waypoint blown up raises no break: it is forgotten once its cell is seen without it.
    for (final w in [..._all]) {
      if (w.dimension == game.dimension &&
          game.world.isLoaded(w.cell) &&
          game.world.blockNameAt(w.cell) != Waypoints.block) {
        _forget(w.dimension, w.cell);
      }
    }
  }

  // The first `Waypoint N` no waypoint is called.
  String _nextLabel() {
    final taken = {for (final w in _all) w.label};
    var n = 1;
    while (taken.contains('Waypoint $n')) {
      n++;
    }
    return 'Waypoint $n';
  }

  void _forget(String dimension, IVec3 cell) => _all.removeWhere((w) => w.dimension == dimension && w.cell == cell);

  static Vector3 _centre(IVec3 c) => Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5);

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => [
    for (final w in _all)
      {
        'cell': [w.cell.x, w.cell.y, w.cell.z],
        'dimension': w.dimension,
        'label': w.label,
      },
  ];

  @override
  void restore(VoxelGame game, Object? saved) {
    _all.clear();
    for (final row in (saved! as List<Object?>).cast<Map<String, Object?>>()) {
      final c = (row['cell']! as List<Object?>).cast<int>();
      final dimension = row['dimension']! as String;
      if (!game.spec.dimensionIds.contains(dimension)) throw FormatException('a waypoint in no dimension $dimension');
      _all.add((cell: IVec3(c[0], c[1], c[2]), dimension: dimension, label: row['label']! as String));
    }
  }
}
