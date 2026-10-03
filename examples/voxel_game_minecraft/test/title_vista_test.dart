import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart' show ChunkSize;
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/spec/game_title.dart';
import 'package:voxel_game_minecraft/src/ui/title_vista.dart';
import 'package:voxel_scene/voxel_scene.dart' show MirroredCamera, SkyLook;

void main() {
  test('the vista circles a point two blocks over its world, 30 off and 16 up, a turn in 105 s, clear of it', () async {
    final world = GameWorld.headless(
      gameSpec.buildBlocks(),
      [gameSpec.world],
      TitleVista.seed,
      loadRadius: TitleVista.radius,
    );
    final centre = TitleVista.centreOf(world);
    await world.start();
    world.update(centre);
    for (var i = 0; i < 600 && !world.isIdle; i++) {
      await Future<void>.delayed(Duration.zero);
      world.update(centre);
    }
    final ground = centre.y.toInt() - 2;
    expect(centre.x, 8.5);
    expect(centre.z, 8.5);
    expect(world.isSolid(IVec3(8, ground - 1, 8)), isTrue);
    expect(world.isSolid(IVec3(8, ground, 8)), isFalse);

    // Every half degree of the turn, the eye is 3 blocks or more over the
    // highest block under it, a tree's leaves too.
    final air = world.blocks.indexOf('air');
    var clearance = double.infinity;
    for (var a = 0; a < 720; a++) {
      final eye = TitleVista.eyeAt(centre, a * math.pi / 360.0);
      final x = eye.x.floor(), z = eye.z.floor();
      var y = ChunkSize.sizeY - 1;
      while (y >= 0 && world.getBlockXYZ(x, y, z) == air) {
        y--;
      }
      clearance = math.min(clearance, eye.y - (y + 1));
    }
    expect(clearance, greaterThanOrEqualTo(3.0));

    for (final angle in [0.0, 1.0, math.pi, 5.0]) {
      final eye = TitleVista.eyeAt(centre, angle);
      expect(eye.y - centre.y, TitleVista.orbitHeight);
      expect(Vector2(eye.x - centre.x, eye.z - centre.z).length, closeTo(30.0, 1e-4));
    }
    expect(TitleVista.eyeAt(centre, 0.0), centre + Vector3(30.0, 16.0, 0.0));
    expect(2 * math.pi / TitleVista.orbitSpeed, closeTo(104.7, 0.1));

    final camera = TitleVista.cameraAt(centre, 1.0) as MirroredCamera;
    expect(camera.position, TitleVista.eyeAt(centre, 1.0));
    expect(camera.target, centre);
    expect(camera.fovRadiansY, closeTo(65.0 * math.pi / 180.0, 1e-6));
  });

  test('the vista stands in a clear morning, the sun 48 degrees up, and hazes its far side', () {
    final look = SkyLook.at(TitleVista.hour, sunStep: 0.5 * math.pi / 180.0);
    expect(math.asin(look.sunDirection.y) * 180.0 / math.pi, closeTo(48.0, 0.5));
    expect(look.skyLight, 1.0);
    expect(TitleVista.hour, lessThan(0.5));
    // A thing across the world (some 80 m off) is a third haze, not lost in it.
    expect(1.0 - math.exp(-TitleVista.haze.density * 80.0), closeTo(0.38, 0.01));
  });

  test('the title is the vista over the meadow, at the game\'s music volume', () {
    expect(gameTitle(credits: const [], background: TitleVista.builder).background, TitleVista.builder);
    expect(gameTitle(credits: const []).background, isNull);
    expect(gameSpec.sounds.music!.tracks, contains(TitleVista.track));
    final settings = GameSettings.of(gameSpec).copyWith(volume: 0.5, musicVolume: 0.4);
    expect(TitleVista.musicGain(settings), closeTo(0.2, 1e-12));
  });
}
