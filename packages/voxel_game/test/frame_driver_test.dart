import 'package:flutter/widgets.dart';
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

/// The frames `VoxelGameWidget` runs, from its tickers or from the driver's
/// timer, over a headless game: the widget itself needs Flutter GPU.
void main() {
  Future<VoxelGame> start(WidgetTester tester) async {
    final game = (await tester.runAsync(() async {
      final game = await VoxelGame.startHeadless(_spec);
      game.spawner.enabled = false;
      for (var i = 0; i < 600 && !game.ready; i++) {
        game.frame(1 / 60);
        await Future<void>.delayed(Duration.zero);
      }
      return game;
    }))!;
    expect(game.ready, isTrue);
    addTearDown(game.dispose);
    return game;
  }

  FrameDriver drive(WidgetTester tester, VoxelGame game) {
    final driver = FrameDriver(game.frame);
    addTearDown(driver.dispose);
    return driver;
  }

  void lifecycle(WidgetTester tester, AppLifecycleState state) => tester.binding.handleAppLifecycleStateChanged(state);

  testWidgets('a hidden window steps from the timer, and asks for no frame', (tester) async {
    final game = await start(tester);
    final driver = drive(tester, game);
    expect(driver.source, FrameSource.ticker);
    final time = game.time, frames = game.frames.value;
    // A desktop window covered by another: inactive, then hidden.
    lifecycle(tester, AppLifecycleState.hidden);
    expect(driver.source, FrameSource.timer);
    expect(tester.binding.framesEnabled, isFalse);
    await tester.binding.delayed(const Duration(seconds: 1));
    expect(game.time - time, closeTo(1.0, 0.05), reason: 'a second hidden is a second of steps');
    expect(game.frames.value - frames, 62, reason: 'a frame every 16 ms');
    expect(tester.binding.hasScheduledFrame, isFalse);
    lifecycle(tester, AppLifecycleState.resumed);
  });

  testWidgets('a ticker\'s frame while hidden runs nothing: one source at a time', (tester) async {
    final game = await start(tester);
    final driver = drive(tester, game);
    lifecycle(tester, AppLifecycleState.hidden);
    final time = game.time, frames = game.frames.value;
    // A metrics change forces a frame even hidden.
    driver.tickerFrame(1 / 60);
    expect(game.frames.value, frames);
    expect(game.time, time);
    lifecycle(tester, AppLifecycleState.resumed);
  });

  testWidgets('shown again, the ticker takes over with no jump and the timer stops', (tester) async {
    final game = await start(tester);
    final driver = drive(tester, game);
    lifecycle(tester, AppLifecycleState.hidden);
    await tester.binding.delayed(const Duration(seconds: 1));
    lifecycle(tester, AppLifecycleState.inactive);
    expect(driver.source, FrameSource.handOver);
    var time = game.time, frames = game.frames.value;
    // The ticker's first delta carries the whole hidden spell.
    driver.tickerFrame(1.0);
    expect(game.frames.value, frames + 1);
    expect(game.time, time, reason: 'the timer has run that second already');
    expect(driver.source, FrameSource.ticker);
    driver.tickerFrame(1 / 60);
    expect(game.time, closeTo(time + 1 / 60, 1e-9));
    time = game.time;
    frames = game.frames.value;
    await tester.binding.delayed(const Duration(seconds: 1));
    expect(game.frames.value, frames, reason: 'the timer stopped: the ticker is the only source');
    expect(game.time, time);
    lifecycle(tester, AppLifecycleState.resumed);
  });

  testWidgets('a window that starts hidden starts on the timer', (tester) async {
    final game = await start(tester);
    lifecycle(tester, AppLifecycleState.hidden);
    final driver = drive(tester, game);
    expect(driver.source, FrameSource.timer);
    final time = game.time;
    await tester.binding.delayed(const Duration(milliseconds: 500));
    expect(game.time, greaterThan(time + 0.4));
    lifecycle(tester, AppLifecycleState.resumed);
  });

  testWidgets('paused stops the timer: a phone in the background is suspended anyway', (tester) async {
    final game = await start(tester);
    final driver = drive(tester, game);
    lifecycle(tester, AppLifecycleState.hidden);
    lifecycle(tester, AppLifecycleState.paused);
    expect(driver.source, FrameSource.handOver);
    final frames = game.frames.value;
    await tester.binding.delayed(const Duration(seconds: 1));
    expect(game.frames.value, frames);
    lifecycle(tester, AppLifecycleState.resumed);
  });
}
