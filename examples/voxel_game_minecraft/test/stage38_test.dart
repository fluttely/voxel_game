import 'dart:io';
import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/game/music.dart';
import 'package:voxel_game_minecraft/src/game/settings.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_engine/core.dart';

/// Stage 38's pure pieces: the music's own volume, and a pen a mob cannot
/// plan its way out of. The fence heights (a block for the player, a barrier
/// for a mob) and the ladder's collider are pinned in voxel_core's
/// `physics_test`.
void main() {
  test('the music volume is saved apart from the master volume, and clamped', () {
    final s = Settings.instance
      ..volume = 0.8
      ..musicVolume = 0.25;
    final text = s.toConfig();
    expect(text, contains('volume=0.8'));
    expect(text, contains('music_volume=0.25'));
    final dir = Directory.systemTemp.createTempSync('stage38_settings');
    s.path = '${dir.path}/settings.cfg';
    expect(s.save(), isTrue);
    s
      ..volume = 1.0
      ..musicVolume = 1.0;
    expect(s.loadFile(), isTrue);
    expect([s.volume, s.musicVolume], [0.8, 0.25]);
    s.fromConfig('[audio]\n\nvolume=0.5\nmusic_volume=4\n');
    expect([s.volume, s.musicVolume], [0.5, 1.0]);
    s.fromConfig('[audio]\n\nmusic_volume=-1\n');
    expect(s.musicVolume, 0.0);
    dir.deleteSync(recursive: true);
  });

  test('the music volume reaches the player without an audio device', () {
    Music.instance.setVolume(0.3);
    expect(Music.instance.volume, 0.3);
    Music.instance.setVolume(1.0);
  });

  test('a mob never plans a path over a fence line', () {
    const floorY = 10;
    final w = VoxelWorld(seedValue: 42, loadRadius: 1);
    final c = Uint8List(VoxelWorld.volume);
    for (var i = 0; i < 16 * 16 * floorY; i++) {
      c[i] = Blocks.indexOf('stone');
    }
    w.chunks[(x: 0, z: 0)] = c;
    for (var z = 0; z < 16; z++) {
      w.setBlock(IVec3(8, floorY, z), Blocks.indexOf('oak_fence'));
    }
    expect(Pathfinder.walkable(w, const IVec3(8, floorY + 1, 7), Blocks.pathCosts), isFalse, reason: 'a fence top is no floor');
    final path = Pathfinder.find(w, const IVec3(4, floorY, 7), const IVec3(12, floorY, 7), costs: Blocks.pathCosts);
    expect(path.every((p) => p.x < 8.0), isTrue, reason: 'the best it can do is wait at the fence');

    // A solid block in the line is a step again.
    w.setBlock(const IVec3(8, floorY, 7), Blocks.indexOf('oak_planks'));
    final over = Pathfinder.find(w, const IVec3(4, floorY, 7), const IVec3(12, floorY, 7), costs: Blocks.pathCosts);
    expect([over.last.x, over.last.z], [12.5, 7.5], reason: 'reaches the goal');
    expect(over.any((p) => p.x.floor() == 8 && p.y == floorY + 1), isTrue);
  });
}
