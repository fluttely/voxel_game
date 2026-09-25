import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

void main() {
  test('the scene scale is the render scale until the pixel-ratio cap lowers it', () {
    const free = GraphicsSpec(renderScale: 0.75);
    expect(free.sceneScale(2.0), 0.75);
    expect(free.sceneScale(3.0), 0.75);
    const capped = GraphicsSpec(maxPixelRatio: 1.5);
    expect(capped.sceneScale(1.0), 1.0);
    expect(capped.sceneScale(3.0), 0.5);
    const both = GraphicsSpec(renderScale: 0.4, maxPixelRatio: 1.5);
    expect(both.sceneScale(3.0), 0.4, reason: 'already under the cap');
  });

  test('the desktop preset is the look the kit had, the phone one is cheaper everywhere', () {
    const d = GraphicsSpec.desktop, p = GraphicsSpec.phone;
    expect(d.renderScale, 1.0);
    expect(d.maxPixelRatio, isNull);
    expect(d.antiAliasing, AntiAliasingMode.msaa);
    expect(
      (d.shadows.cascades, d.shadows.resolution, d.shadows.distance, d.shadows.sunStepDegrees),
      (4, 2048, 110.0, 0.5),
    );
    expect(p.antiAliasing, AntiAliasingMode.fxaa);
    expect(p.shadows.cascades, lessThan(d.shadows.cascades));
    expect(p.shadows.resolution, lessThan(d.shadows.resolution));
    expect(p.shadows.distance, lessThan(d.shadows.distance));
    expect(p.shadows.sunStepDegrees, greaterThan(d.shadows.sunStepDegrees));
    expect(p.sceneScale(3.0), 0.5);
  });

  const flat = VoxelGameSpec(
    blocks: [BlockType('stone', color: 0x808080), BlockType.liquid('water', color: 0x3366CC)],
    world: WorldGenSpec(
      terrain: TerrainRecipe.flat(20),
      caves: CaveSpec.none,
      biomes: [Biome('plain', top: 'stone')],
    ),
  );

  for (final (platform, preset) in [
    (TargetPlatform.macOS, GraphicsSpec.desktop),
    (TargetPlatform.windows, GraphicsSpec.desktop),
    (TargetPlatform.iOS, GraphicsSpec.phone),
    (TargetPlatform.android, GraphicsSpec.phone),
  ]) {
    test('a spec without graphics gets the ${platform.name} preset', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final game = await VoxelGame.startHeadless(flat, loadRadius: 3);
      addTearDown(game.dispose);
      expect(game.graphics, same(preset));
    });
  }

  test('a spec with graphics keeps them, and the view distance is the loaded window', () async {
    final game = await VoxelGame.startHeadless(flat.copyWith(graphics: GraphicsSpec.phone), loadRadius: 3);
    addTearDown(game.dispose);
    expect(game.graphics, same(GraphicsSpec.phone));
    expect(game.viewDistance, 48.0);
  });
}
