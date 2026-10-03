import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/ui/game_hud.dart';

class _Heard implements SoundPlayer {
  final List<String> played = [];

  @override
  void play(String name, {double volumeDb = 0.0, double pitch = 1.0}) => played.add(name);
}

/// The game's HUD over a running game, on the `GameSurface` the kit's widget
/// shows it on.
void main() {
  Future<VoxelGame> start(WidgetTester tester) async {
    final game = (await tester.runAsync(() async {
      final game = await VoxelGame.startHeadless(gameSpec);
      game.spawner.enabled = false;
      for (var i = 0; i < 600 && !game.ready; i++) {
        game.frame(1 / 60);
        await Future<void>.delayed(Duration.zero);
      }
      return game;
    }))!;
    expect(game.ready, isTrue);
    game.input.wantCapture = true;
    await tester.pumpWidget(
      MaterialApp(
        home: GameSurface(
          game: game,
          world: const ColoredBox(color: Colors.black),
          hud: GameHud.builder,
        ),
      ),
    );
    return game;
  }

  // One step of the game, then the HUD's rebuild.
  Future<void> step(WidgetTester tester, VoxelGame game) async {
    game.frame(1 / 30);
    await tester.pump();
  }

  Finder edge() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LowHealthEdge);

  testWidgets('the clock line reads the hour and the biome, then night and the weather', (tester) async {
    final game = await start(tester);
    expect(find.byType(DefaultHud), findsOneWidget, reason: 'the game\'s pieces are on the kit\'s HUD');
    game.timeOfDay = 0.5;
    await step(tester, game);
    expect(find.text('12:00   Plains'), findsOneWidget);
    game.timeOfDay = 0.9;
    game.weather.set(WeatherKind.storm, now: true);
    await step(tester, game);
    expect(find.text('21:36   Plains   (night)   Storm'), findsOneWidget);
    game.dispose();
  });

  testWidgets('a dimension with a still sky is named instead, with no hour', (tester) async {
    final game = await start(tester);
    game.travel('underworld');
    await step(tester, game);
    expect(find.text('Underworld'), findsOneWidget);
    expect(GameHud.clockOf(game), 'Underworld');
    game.dispose();
  });

  testWidgets('the creature in the crosshair is named with its health, under the boss bar the clock', (tester) async {
    final game = await start(tester);
    // A cow 2 m ahead, looked down at: its back is under the eye.
    final p = game.player..pitch = -0.45;
    final cow = game.spawnMob('cow', p.position + Vector3(0, 0, -2));
    p.yaw = 0.0;
    await step(tester, game);
    expect(p.aimedMob, cow);
    expect(find.text('Cow  12/12'), findsOneWidget);
    double clockTop() => tester
        .widget<Padding>(find.ancestor(of: find.textContaining('Plains'), matching: find.byType(Padding)).first)
        .padding
        .vertical;
    expect(clockTop(), 12);
    game.spawnMob('yeti', p.position + Vector3(6, 0, 6));
    await step(tester, game);
    expect(game.boss, isNotNull);
    expect(clockTop(), 12 + GameHud.underBossBar);
    game.dispose();
  });

  testWidgets('a red edge pulses while the health is low, and the heart is heard with it', (tester) async {
    final game = await start(tester);
    final heard = _Heard();
    game.sounds = heard;
    final p = game.player;
    await step(tester, game);
    expect(edge(), findsNothing);
    p.hp = 4;
    // Two seconds: a beat at once and one every 0.9 s.
    for (var i = 0; i < 60; i++) {
      await step(tester, game);
    }
    expect(edge(), findsOneWidget);
    expect(heard.played.where((n) => n == 'heartbeat').length, 3);
    p.hp = p.maxHp;
    heard.played.clear();
    for (var i = 0; i < 60; i++) {
      await step(tester, game);
    }
    expect(edge(), findsNothing);
    expect(heard.played, isNot(contains('heartbeat')));
    game.dispose();
  });

  test('the edge\'s strength stays between 0.15 and 0.55, about once a second', () {
    final seen = [for (var t = 0.0; t < 2.0; t += 0.01) LowHealthEdge.strength(t)];
    expect(seen.every((s) => s >= 0.15 - 1e-9 && s <= 0.55 + 1e-9), isTrue);
    expect(LowHealthEdge.strength(0.0), 0.35);
  });
}
