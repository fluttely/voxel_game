import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/classes/class_system.dart';
import 'package:voxel_game_minecraft/src/ui/game_hud.dart';
import 'package:voxel_game_minecraft/src/journal/journal_screen.dart';
import 'package:voxel_game_minecraft/src/journal/tutorial.dart';
import 'package:voxel_game_minecraft/src/journal/stats_screen.dart';
import 'package:voxel_game_minecraft/src/ui/controls_screen.dart';

class _Heard implements SoundPlayer {
  final List<String> played = [];

  @override
  void play(String name, {double volumeDb = 0.0, double pitch = 1.0}) => played.add(name);
}

/// The game's HUD over a running game, on the `GameSurface` the kit's widget
/// shows it on.
void main() {
  Future<VoxelGame> start(WidgetTester tester, {bool tutorialDone = true}) async {
    final game = (await tester.runAsync(() async {
      final game = await VoxelGame.startHeadless(
        gameSpec,
        options: const {'class': 'warrior'},
        settings: GameSettings.of(gameSpec).copyWith(game: {Tutorial.doneKey: tutorialDone}),
      );
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

  testWidgets('the class\'s stamina and mana are bars, its abilities listed with what is left of a cooldown', (
    tester,
  ) async {
    final game = await start(tester);
    expect(find.text('Stamina'), findsOneWidget);
    expect(find.text('Mana'), findsOneWidget);
    expect(GameHud.abilitiesOf(game), ['[R] Whirlwind', '[F] Shield Bash', '[Alt] Dodge']);
    game.actions.tap('ability');
    await step(tester, game);
    expect(find.textContaining('[R] Whirlwind  8s'), findsOneWidget);
    game.dispose();
  });

  testWidgets('the journal spends a talent point on a rank, and no more than there are', (tester) async {
    final game = await start(tester);
    ClassSystem.of(game).points = 1;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: JournalScreen(game))));
    expect(find.text('Warrior talents'), findsOneWidget);
    expect(find.text('Talent points: 1   (you get one each level)'), findsOneWidget);
    expect(find.text('Rage  0/3', skipOffstage: false), findsOneWidget, reason: 'the class\'s own, after the six');
    await tester.tap(find.widgetWithText(FilledButton, 'Learn').first);
    await step(tester, game);
    expect(find.text('Vitality  1/3'), findsOneWidget);
    expect(find.text('Talent points: 0   (you get one each level)'), findsOneWidget);
    for (final b in tester.widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Learn'))) {
      expect(b.onPressed, isNull, reason: 'no point left');
    }
    game.dispose();
  });

  testWidgets('the journal\'s other tabs: the creatures met, the achievements, the quests', (tester) async {
    final game = await start(tester);
    game.spawnMob('pig', game.player.position + Vector3(3, 0.5, 0));
    game.step(1 / 60);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: JournalScreen(game))));
    expect(find.text('Talents'), findsOneWidget);
    await tester.tap(find.text('Creatures'));
    await tester.pumpAndSettle();
    expect(find.text('Pig'), findsOneWidget);
    expect(find.textContaining('Health 10'), findsOneWidget);
    expect(find.text('???'), findsWidgets);
    await tester.tap(find.text('Achievements'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 22 unlocked'), findsOneWidget);
    await tester.tap(find.text('Quests'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 12 quests done'), findsOneWidget);
    expect(find.text('Punch or chop 8 logs   0/8   20 XP'), findsOneWidget);
    game.player.pickUp('oak_log', 3);
    await step(tester, game);
    expect(find.text('Punch or chop 8 logs   3/8   20 XP'), findsOneWidget, reason: 'the world goes on behind it');
    game.dispose();
  });

  testWidgets('the quest at hand is at the top right, with how far it is', (tester) async {
    final game = await start(tester);
    expect(find.text('Quest: Gather wood'), findsOneWidget);
    expect(find.text('Punch or chop 8 logs  (0/8)'), findsOneWidget);
    game.player.pickUp('spruce_log', 2);
    await step(tester, game);
    expect(find.text('Punch or chop 8 logs  (2/8)'), findsOneWidget);
    game.dispose();
  });

  testWidgets('the tutorial\'s card shows the step at hand, and its button skips it all', (tester) async {
    final game = await start(tester, tutorialDone: false);
    await step(tester, game);
    expect(find.text('Step 1/10   '), findsOneWidget);
    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('Press W A S D to walk around.'), findsOneWidget);
    await tester.tap(find.text('Skip tutorial (F6)'));
    await step(tester, game);
    expect(find.text('Walk'), findsNothing);
    game.dispose();
  });

  testWidgets('the stats and the controls are screens of the game menu; F1 opens the controls', (tester) async {
    final game = await start(tester);
    expect(gameSpec.screens.values.where((s) => s.listedIn(game)).map((s) => s.menu), [
      'Journal',
      'Map',
      'Stats',
      'Controls',
    ], reason: "an open world's menu: Playground is a playground's");
    game.raise(const BlockBroken('stone', IVec3(0, 0, 0)));
    game.step(1 / 60);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatsScreen(game))));
    expect(find.textContaining('Blocks broken  1'), findsOneWidget);
    expect(StatsScreen.linesOf(game).first, 'Level 0');
    game.actions.tap('controls');
    game.step(1 / 60);
    expect(game.screen.value, const DeclaredScreen('controls'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ControlsScreen(game))));
    expect(find.text('Keyboard and mouse'), findsOneWidget);
    await tester.tap(find.text('Back to the game'));
    expect(game.screen.value, isNull);
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
