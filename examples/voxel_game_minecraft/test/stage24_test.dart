import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/core/species.dart';
import 'package:voxel_game_minecraft/src/entities/boat.dart';
import 'package:voxel_game_minecraft/src/entities/item_drop.dart';
import 'package:voxel_game_minecraft/src/entities/mob.dart';
import 'package:voxel_game_minecraft/src/game/game.dart';
import 'package:voxel_game_minecraft/src/game/quests.dart';
import 'package:voxel_game_minecraft/src/game/settings.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 24's pure pieces (Godot `--stage24` covers the rest in the app): the
/// save keys for boats, tamed mobs, drops, visited chunks and discovered
/// structures, the settings file, the quests tab and the render-distance trim.
void main() {
  /// Through JSON text, the way the save file carries it.
  Map<String, dynamic> viaJson(Map<String, Object> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  test('a boat and a drop save their Godot keys', () {
    final boat = Boat()
      ..position = Vector3(3.5, 47.2, -8.25)
      ..yaw = 0.4;
    final b = viaJson(boat.toJson());
    expect(b.keys, unorderedEquals(['pos', 'yaw']));
    expect(b['pos'], [3.5, closeTo(47.2, 1e-6), -8.25]);
    expect(b['yaw'], closeTo(0.4, 1e-9));
    final drop = ItemDrop()
      ..itemId = 'apple'
      ..count = 3
      ..bonus = 2
      ..position = Vector3(1, 2, 3);
    final d = viaJson(drop.toJson());
    expect(d, {'item': 'apple', 'count': 3, 'bonus': 2, 'pos': [1.0, 2.0, 3.0]});
  });

  test('a tamed mob round-trips: level, hp, tame state and facing', () {
    final wolf = Mob()
      ..species = Species.def('wolf')
      ..position = Vector3(10.5, 50, 4.5)
      ..mobLevel = 3
      ..maxHp = 30
      ..hp = 21
      ..tamed = true;
    final saved = viaJson(wolf.toJson());
    expect(saved.keys, unorderedEquals(['species', 'pos', 'hp', 'max_hp', 'level', 'affix', 'tamed', 'name', 'yaw', 'trades', 'home']));
    expect(saved['species'], 'wolf');
    expect(saved['name'], Species.def('wolf').name);
    final back = Mob()..species = Species.def('wolf');
    back.fromJson(saved);
    expect(back.tamed, isTrue);
    expect(back.barVisible, isTrue);
    expect(back.state, MobState.idle);
    expect(back.mobLevel, 3);
    expect(back.hp, 21);
    expect(back.maxHp, 30);
    expect(back.position, Vector3(10.5, 50, 4.5));
  });

  test('visited chunks and discovered structures survive the save text', () {
    final visited = <ChunkPos>{(x: 0, z: 0), (x: 1, z: 0), (x: -3, z: 7)};
    final keys = jsonDecode(jsonEncode(Game.encodeVisited(visited))) as List<dynamic>;
    expect(keys, contains('-3,7'));
    expect(Game.decodeVisited(keys), visited);
    final found = {const IVec3(37, 64, 5): 5, const IVec3(-414, 54, -274): 8};
    final text = jsonDecode(jsonEncode(Game.encodeStructures(found))) as Map<String, dynamic>;
    expect(text['37,64,5'], 5);
    expect(Game.decodeStructures(text), found);
  });

  test('settings write Godot ConfigFile text, read it back and clamp', () {
    final s = Settings.instance;
    s
      ..renderRadius = 6
      ..sensitivity = 1.5
      ..fov = 80.0
      ..volume = 0.35
      ..weather = false
      ..showFps = true;
    final text = s.toConfig();
    expect(text, contains('[video]'));
    expect(text, contains('render_radius=6'));
    expect(text, contains('weather=false'));
    final dir = Directory.systemTemp.createTempSync('stage24_settings');
    s.path = '${dir.path}/settings.cfg';
    expect(s.save(), isTrue);
    s
      ..renderRadius = 8
      ..sensitivity = 1.0
      ..fov = 72.0
      ..volume = 1.0
      ..weather = true
      ..showFps = false;
    expect(s.loadFile(), isTrue);
    expect([s.renderRadius, s.sensitivity, s.fov, s.volume, s.weather, s.showFps], [6, 1.5, 80.0, 0.35, false, true]);
    // Godot's own file shape, with out-of-range values.
    s.fromConfig('[video]\n\nrender_radius=14\nfov=30.0\n\n[input]\n\nsensitivity=9\n\n[audio]\n\nvolume=-1\n');
    expect([s.renderRadius, s.fov, s.sensitivity, s.volume], [10, 60.0, 3.0, 0.0]);
    dir.deleteSync(recursive: true);
  });

  test('the quests tab lists the chain: done, active, locked', () {
    final log = QuestLog()
      ..index = 3
      ..progress = 1;
    final entries = JournalTabs.questEntries(log);
    expect(entries.length, 12);
    expect(JournalTabs.names[JournalTabs.quests], 'Quests');
    expect(entries.take(3).every((e) => e.state == 'done' && e.progress == e.n), isTrue);
    expect(entries[3].state, 'active');
    expect(entries[3].progress, 1);
    expect(entries.skip(4).every((e) => e.state == 'locked' && e.progress == 0), isTrue);
    expect(JournalTabs.questEntries(QuestLog()).first.title, 'Gather wood');
  });

  test('a smaller render distance drops the far chunks at once', () {
    final w = VoxelWorld(seedValue: 42, loadRadius: 8);
    for (var x = -9; x <= 9; x++) {
      for (var z = -9; z <= 9; z++) {
        w.chunks[(x: x, z: z)] = Uint8List(1);
      }
    }
    w.updateAround(Vector3(8, 60, 8)); // centre chunk (0, 0)
    expect(w.chunks.length, 19 * 19);
    w.loadRadius = 6;
    w.unloadRadius = 8;
    w.trimWindow();
    expect(w.chunks.length, 15 * 15); // the load radius plus its generated ring
    expect(w.isLoaded(const IVec3(7 * 16 + 1, 50, 0)), isTrue);
    expect(w.isLoaded(const IVec3(8 * 16 + 1, 50, 0)), isFalse);
  });
}
