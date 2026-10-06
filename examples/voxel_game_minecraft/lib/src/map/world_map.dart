import 'package:voxel_engine/core.dart' show ChunkPos, ChunkStreamer;
import 'package:voxel_game/voxel_game.dart';

import 'map_picture.dart';

/// The map of this world: the chunks the player has stood in, per dimension
/// ([exploredIn]), a look a second; and how the map shows, cycled by the map
/// action ([action], M): the minimap in the HUD's corner ([minimap]), then
/// the whole map as a screen ([screen]) in its place, then neither.
///
/// What the map draws of the world is [picture]'s; what it marks on it (the
/// structures found, `Structures.foundIn`, the waypoints, the spawn, the
/// tamed mounts) and the creatures are `MapPainter`'s.
///
/// Saved with the world (under `map`): the chunks explored.
class WorldMap extends SavedSystem {
  /// The key of the explored chunks in the save.
  static const String key = 'map';

  /// The action that cycles the map: the minimap, the whole map, off.
  static const String action = 'map';

  /// The screen of the whole map.
  static const String screen = 'map';

  /// Seconds between two looks at the chunk the player stands in.
  static const double lookEvery = 1.0;

  /// The map of [game].
  static WorldMap of(VoxelGame game) => game.system<WorldMap>();

  final Map<String, Set<ChunkPos>> _explored = {};
  double _lookIn = 0.0;

  /// Whether the minimap is shown in the HUD's corner.
  bool minimap = false;

  /// The world as the map draws it, painted while the map shows.
  final MapPicture picture = MapPicture();

  /// The map action's button on the device the player last used, as the
  /// map's hints name it: null on a phone, whose button shows its icon.
  static String? keyOf(VoxelGame game) => switch (game.input.lastDevice) {
    InputDevice.keyboardMouse => 'M',
    InputDevice.gamepad => 'Back',
    InputDevice.touch => null,
  };

  /// The chunks of [dimension] the player has stood in.
  Set<ChunkPos> exploredIn(String dimension) => {...?_explored[dimension]};

  /// One press of the map action: the minimap shows; shown, it gives way to
  /// the whole map; the whole map open, it closes. Over any other screen, or
  /// while the player does not play, nothing.
  void cycle(VoxelGame game) {
    switch (game.screen.value) {
      case DeclaredScreen(id: screen):
        game.closeScreen();
      case null when game.gameplay && !minimap:
        minimap = true;
      case null when game.gameplay:
        minimap = false;
        game.openScreen(const DeclaredScreen(screen));
      default:
    }
  }

  @override
  void tick(VoxelGame game, double dt) {
    if (game.actions.justPressed(action)) cycle(game);
    _lookIn -= dt;
    if (_lookIn > 0.0) return;
    _lookIn = lookEvery;
    (_explored[game.dimension] ??= {}).add(ChunkStreamer.chunkOf(IVec3.floor(game.player.position)));
  }

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {
    for (final MapEntry(key: dimension, value: chunks) in _explored.entries)
      dimension: [
        for (final c in chunks) [c.x, c.z],
      ],
  };

  @override
  void restore(VoxelGame game, Object? saved) {
    _explored.clear();
    for (final MapEntry(key: dimension, value: rows) in (saved! as Map<String, Object?>).entries) {
      if (!game.spec.dimensionIds.contains(dimension)) throw FormatException('a map of no dimension $dimension');
      _explored[dimension] = {
        for (final c in (rows! as List<Object?>).cast<List<Object?>>()) (x: c[0]! as int, z: c[1]! as int),
      };
    }
  }
}
