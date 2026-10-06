import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/spec/game_title.dart';

void main() {
  final roadmap = File('ROADMAP.md').readAsStringSync();

  test('the credits frame every stage row of the roadmap, in its order', () {
    final stages = stagesOf(roadmap);
    expect(stages.length, roadmap.split('\n').where((l) => RegExp(r'^\|\s*\d+[ab]?\s*\|').hasMatch(l)).length);
    expect(stages.first, 'Stage 0 — Worktree + project skeleton');
    expect(stages, contains('Stage 29 — The Underworld, a second dimension'));
    final credits = creditsOf(roadmap);
    expect(credits.first, 'VOXEL MINECRAFT');
    expect(credits, contains('the voxel kit: voxel_game over voxel_scene, voxel_engine and sound_recipes'));
    expect(
      credits,
      containsAllInOrder(['Engine', 'Music and sound', 'Lineage', 'Stages', ...stages, 'Thanks for playing.']),
    );
    expect(stages.any((s) => s.contains('**') || s.endsWith('.')), isFalse);
  });

  test('a stage is its bold lead, else its cell cut at the first sentence; anything else is no stage', () {
    const text =
        '| # | Stage | Status |\n|:--|:---|:---|\n'
        '| 3 | Streaming world + delta save. More words (x) | ✅ | |\n'
        '| 21a | **Four structures.** Details | ✅ | |\n'
        '| 7 | Day/night (with hunger) and death | ✅ | |\n'
        'not a row | 9 | nope |\n';
    expect(stagesOf(text), [
      'Stage 3 — Streaming world + delta save',
      'Stage 21a — Four structures',
      'Stage 7 — Day/night',
    ]);
    expect(creditsAround(['Stage 1 — A']).last, 'Esc closes');
  });

  testWidgets('the title offers the game, its credits, and a class and a kind for a new world', (tester) async {
    final dir = Directory.systemTemp.createTempSync('game_title_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(Directory('${dir.path}/worlds'));
    final settings = SettingsStore(File('${dir.path}/settings.json'));
    final picked = <TitleChoice>[];
    Future<void> mount() => tester.pumpWidget(
      MaterialApp(
        home: TitleScreen(
          spec: gameSpec,
          menu: gameTitle(credits: creditsOf(roadmap)),
          saves: saves,
          settings: settings,
          onChoice: picked.add,
        ),
      ),
    );
    await mount();
    expect(find.text('Voxel Minecraft'), findsOneWidget);
    expect(find.text('a Minecraft clone built on voxel_game'), findsOneWidget);
    for (final b in ['Play', 'Multiplayer', 'Settings', 'Credits']) {
      expect(find.text(b), findsOneWidget);
    }
    await tester.tap(find.text('Credits'));
    await tester.pump();
    expect(find.text('Stage 29 — The Underworld, a second dimension'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.tap(find.text('New world'));
    await tester.pump();
    expect(find.text('Warrior'), findsOneWidget);
    expect(find.text('Open world'), findsOneWidget);
    await tester.tap(find.text('Warrior'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mage').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open world'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playground').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Arena');
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(picked.single, isA<PlayWorld>().having((c) => c.slot, 'slot', 'arena'));
    final info = saves.info('arena');
    expect(info.options, {'class': 'mage', 'playground': 'playground'});
    expect(
      WorldList.detailsOf(info, gameTitle(credits: const []).worldOptions),
      'Survival · Mage · Playground · seed ${info.seed} · new',
    );
  });

  testWidgets('the title plays the meadow through the kit, at the player\'s music gain, and stops it as it goes', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('game_title_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final settings = SettingsStore(File('${dir.path}/settings.json'));
    settings.write(GameSettings.of(gameSpec).copyWith(volume: 0.5, musicVolume: 0.4));
    await tester.pumpWidget(
      MaterialApp(
        home: TitleScreen(
          spec: gameSpec,
          menu: gameTitle(credits: const []),
          saves: WorldSaves(Directory('${dir.path}/worlds')),
          settings: settings,
          onChoice: (_) {},
        ),
      ),
    );
    await tester.pump();
    final music = GameMusic.playing.value!;
    expect(music.track, 'meadow');
    expect(music.gain, closeTo(0.2, 1e-12));
    await tester.pumpWidget(const SizedBox());
    expect(GameMusic.playing.value, isNull);
    expect(music.track, isNull);
  });
}
