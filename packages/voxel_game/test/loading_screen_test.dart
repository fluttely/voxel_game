import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

const _spec = VoxelGameSpec(
  blocks: [
    BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
    BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType.liquid('water', color: 0x3366CC),
    BlockType.liquid('water_flow', color: 0x3366CC, kind: 'water', source: false),
  ],
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
);

void main() {
  testWidgets('the loading screen names its stage and fills its bar with the window', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoadingScreen(LoadingStage.starting, null)));
    expect(find.text('Starting...'), findsOneWidget);

    final game = (await tester.runAsync(() => VoxelGame.startHeadless(_spec)))!;
    game.spawner.enabled = false;
    await tester.pumpWidget(MaterialApp(home: LoadingScreen(LoadingStage.filling, game)));
    expect(find.text('Generating the world...'), findsOneWidget);
    double bar() => tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value!;
    expect(bar(), 0.0);

    await tester.runAsync(() async {
      for (var i = 0; i < 600 && !game.filled; i++) {
        game.frame(1 / 60);
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pump();
    expect(bar(), 1.0, reason: 'a filled window is a full bar');

    await tester.pumpWidget(MaterialApp(home: LoadingScreen(LoadingStage.warming, game)));
    expect(find.text('Preparing the renderer...'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
    game.dispose();
  });
}
