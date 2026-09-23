import 'dart:convert';
import 'dart:io';

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import '../player/player_spec.dart';

/// What a save holds before a game starts from it: its seed, its edits and
/// the rest as JSON.
class SavedWorld {
  /// A save read from disk.
  const SavedWorld(this.seed, this.edits, this.state);

  /// The world seed the save was made with (it wins over the spec's).
  final int seed;

  /// The world's edits.
  final EditsByDimension edits;

  /// The game's own state: clock, player.
  final Map<String, Object?> state;
}

/// Saved worlds under one [directory], a folder per slot holding `edits.bin`
/// (the edited cells, `EditDeltaCodec`) and `game.json` (the clock and the
/// player: where, looking where, health, the bag, the spawn point).
class WorldSaves {
  /// Saves under [directory].
  WorldSaves(this.directory);

  /// Where the slots live.
  final Directory directory;

  /// The edit file's layout: magic `VXK1`, version 1, one dimension.
  static const EditDeltaCodec codec = EditDeltaCodec(magic: 0x314B5856, version: 1, dimensions: 1);

  Directory _slot(String slot) => Directory('${directory.path}/$slot');

  /// Whether [slot] holds a save.
  bool exists(String slot) => File('${_slot(slot).path}/game.json').existsSync();

  /// Every slot holding a save.
  List<String> list() => !directory.existsSync()
      ? const []
      : [
          for (final e in directory.listSync())
            if (e is Directory && File('${e.path}/game.json').existsSync()) e.uri.pathSegments.where((s) => s.isNotEmpty).last,
        ];

  /// Deletes [slot].
  void delete(String slot) {
    final d = _slot(slot);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  /// Writes [game] to [slot].
  void save(VoxelGame game, String slot) {
    final d = _slot(slot)..createSync(recursive: true);
    File('${d.path}/edits.bin').writeAsBytesSync(codec.encode(game.world.generator.seed, game.world.edits));
    final p = game.player;
    final state = <String, Object?>{
      'version': 1,
      'seed': game.world.generator.seed,
      'time': game.time,
      'timeOfDay': game.timeOfDay,
      'player': {
        'pos': [p.position.x, p.position.y, p.position.z],
        'spawn': [p.spawnPoint.x, p.spawnPoint.y, p.spawnPoint.z],
        'yaw': p.yaw,
        'pitch': p.pitch,
        'hp': p.hp,
        'slot': p.selectedSlot,
        'view': p.cameraMode.name,
        'inventory': p.inventory.toJson(),
      },
    };
    // Written beside and renamed over, so a crash mid-write keeps the old one.
    final tmp = File('${d.path}/game.json.tmp')..writeAsStringSync(jsonEncode(state));
    tmp.renameSync('${d.path}/game.json');
  }

  /// Reads [slot]; throws when it is missing or unreadable.
  SavedWorld read(String slot) {
    final d = _slot(slot);
    final state = jsonDecode(File('${d.path}/game.json').readAsStringSync()) as Map<String, Object?>;
    final edits = File('${d.path}/edits.bin');
    final decoded = edits.existsSync() ? codec.decode(edits.readAsBytesSync()) : null;
    final seed = (state['seed']! as num).toInt();
    return SavedWorld(seed, decoded?.edits ?? <int, Map<ChunkPos, Map<int, int>>>{}, state);
  }

  /// Puts [saved]'s clock and player back into [game] (its edits are handed
  /// to the world before it streams: see `VoxelGame.start`).
  static void restore(VoxelGame game, SavedWorld saved) {
    final s = saved.state;
    game.time = (s['time']! as num).toDouble();
    game.timeOfDay = (s['timeOfDay']! as num).toDouble();
    final p = s['player'] as Map<String, Object?>?;
    if (p == null) return; // a network hello carries the world, not a player
    Vector3 v(Object? o) {
      final l = [for (final e in o! as List<Object?>) (e! as num).toDouble()];
      return Vector3(l[0], l[1], l[2]);
    }

    game.player
      ..restore(v(p['pos']), v(p['spawn']))
      ..yaw = (p['yaw']! as num).toDouble()
      ..pitch = (p['pitch']! as num).toDouble()
      ..hp = (p['hp']! as num).toDouble()
      ..selectedSlot = (p['slot']! as num).toInt()
      ..cameraMode = CameraMode.values.byName(p['view']! as String);
    game.player.inventory.fromJson(p['inventory']! as List<Object?>, known: game.items.has);
  }
}
