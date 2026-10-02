import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  seed: 7,
  sky: SkySpec.alwaysDay,
);

Future<VoxelGame> _start(VoxelGameSpec spec, {SavedWorld? save}) async {
  final game = await VoxelGame.startHeadless(spec, save: save);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
  return game;
}

/// Saves in a fresh folder, on a clock the test turns.
(WorldSaves, void Function(DateTime)) _saves() {
  final dir = Directory.systemTemp.createTempSync('voxel_worlds');
  addTearDown(() => dir.deleteSync(recursive: true));
  var now = DateTime(2026, 10, 2, 14, 3);
  return (WorldSaves(dir, clock: () => now), (t) => now = t);
}

void main() {
  group('WorldSaves.seedOf', () {
    test('a number is itself, any other text its FNV-1a hash, nothing a random seed', () {
      expect(WorldSaves.seedOf('1337'), 1337);
      expect(WorldSaves.seedOf(' -42 '), -42);
      expect(WorldSaves.seedOf('hello'), 1335831723, reason: 'FNV-1a, the same on every run');
      expect(WorldSaves.seedOf('hello'), WorldSaves.seedOf(' hello '));
      expect(
        WorldSaves.seedOf('12345678901234567890'),
        inInclusiveRange(0, 0xFFFFFFFF),
        reason: 'too long for a number: hashed',
      );
      expect(WorldSaves.seedOf('', random: math.Random(3)), math.Random(3).nextInt(1 << 31));
    });
  });

  group('WorldSaves', () {
    test('a world is made in a slot of its own, and only its world.json is written', () {
      final (saves, _) = _saves();
      final a = saves.create('My World!', seed: 99, mode: WorldMode.creative);
      final b = saves.create('  my world ', seed: 5);
      expect(a.slot, 'my_world');
      expect(b.slot, 'my_world_2', reason: 'the slot taken, a number after it');
      expect(b.name, 'my world', reason: 'the name trimmed');
      expect(saves.create('Ünï', seed: 1).slot, 'n', reason: 'only what a folder holds anywhere');
      expect(saves.create('!!!', seed: 1).slot, 'world');
      expect(() => saves.create('   ', seed: 1), throwsArgumentError);

      expect(saves.contains('my_world'), isTrue);
      expect(saves.exists('my_world'), isFalse, reason: 'never played: no saved game');
      final info = saves.info('my_world');
      expect(info.name, 'My World!');
      expect(info.seed, 99);
      expect(info.mode, WorldMode.creative);
      expect(info.saved, isFalse);
      expect(info.created, DateTime(2026, 10, 2, 14, 3));
      expect(info.lastPlayed, isNull);
      expect(info.playTime, Duration.zero);
      expect(Directory('${saves.directory.path}/my_world').listSync().map((e) => e.uri.pathSegments.last), [
        'world.json',
      ]);
    });

    test('the list is every world, the last played or made first, and nothing else', () {
      final (saves, at) = _saves();
      saves.create('Old', seed: 1);
      at(DateTime(2026, 10, 3));
      saves.create('New', seed: 2);
      Directory('${saves.directory.path}/notes').createSync();
      Directory('${saves.directory.path}/.trash').createSync();
      expect(saves.list()..sort(), ['new', 'old']);
      expect([for (final w in saves.worlds()) w.name], ['New', 'Old']);
    });

    test('a rename keeps the slot', () {
      final (saves, _) = _saves();
      final w = saves.create('First', seed: 1);
      final renamed = saves.rename(w.slot, '  Second ');
      expect(renamed.slot, w.slot);
      expect(saves.info(w.slot).name, 'Second');
      expect(saves.info(w.slot).seed, 1);
      expect(() => saves.rename(w.slot, ' '), throwsArgumentError);
    });

    test('a save keeps the world.json: played now, for the game\'s time', () async {
      final (saves, at) = _saves();
      final w = saves.create('Kept', seed: 31, mode: WorldMode.survival);
      at(DateTime(2026, 10, 4, 9));
      final game = await _start(saves.info(w.slot).applyTo(_spec));
      expect(game.world.generator.seed, 31, reason: 'a fresh world grows from its seed');
      game.time = 125.5;
      saves.save(game, w.slot);

      final info = saves.info(w.slot);
      expect(info.name, 'Kept');
      expect(info.mode, WorldMode.survival);
      expect(info.saved, isTrue);
      expect(info.created, DateTime(2026, 10, 2, 14, 3), reason: 'made when it was made');
      expect(info.lastPlayed, DateTime(2026, 10, 4, 9));
      expect(info.playTime, const Duration(seconds: 125, milliseconds: 500));
      expect(saves.read(w.slot).seed, 31);
    });

    test('a slot saved before world.json lists from its game.json, loads, and gets one on its next save', () async {
      final (saves, at) = _saves();
      final game = await _start(_spec);
      game.time = 30;
      saves.save(game, 'world1');
      File('${saves.directory.path}/world1/world.json').deleteSync();

      final old = saves.info('world1');
      expect(old.name, 'world1');
      expect(old.seed, 7);
      expect(old.mode, isNull, reason: 'it plays as the game declares');
      expect(old.created, isNull, reason: 'when it was made is not known');
      expect(old.saved, isTrue);
      expect(old.lastPlayed, File('${saves.directory.path}/world1/game.json').lastModifiedSync());
      expect(old.playTime, const Duration(seconds: 30));
      expect(saves.list(), ['world1']);

      final back = await _start(old.applyTo(_spec), save: saves.read('world1'));
      expect(back.world.generator.seed, 7);
      at(DateTime(2026, 10, 5));
      saves.save(back, 'world1');
      final now = saves.info('world1');
      expect(now.name, 'world1');
      expect(now.created, isNull);
      expect(now.lastPlayed, DateTime(2026, 10, 5));
      expect(saves.rename('world1', 'Home').name, 'Home');
    });

    test('a slot that was no world is made on its first save', () async {
      final (saves, _) = _saves();
      final game = await _start(_spec);
      saves.save(game, 'fresh');
      final info = saves.info('fresh');
      expect(info.name, 'fresh');
      expect(info.created, DateTime(2026, 10, 2, 14, 3));
      expect(info.lastPlayed, DateTime(2026, 10, 2, 14, 3));
    });

    test('a world.json of another version throws', () {
      final (saves, _) = _saves();
      final w = saves.create('Later', seed: 1);
      final file = File('${saves.directory.path}/${w.slot}/world.json');
      file.writeAsStringSync(
        jsonEncode({...jsonDecode(file.readAsStringSync()) as Map<String, Object?>, 'version': 2}),
      );
      expect(() => saves.info(w.slot), throwsStateError);
    });
  });

  test('a world plays with its seed, and its mode when it has one', () {
    const info = WorldInfo(slot: 's', name: 'S', seed: 404, saved: false, mode: WorldMode.creative);
    final creative = info.applyTo(_spec);
    expect(creative.seed, 404);
    expect(creative.player.creative, isTrue);
    expect(creative.blocks, same(_spec.blocks));
    const declared = WorldInfo(slot: 's', name: 'S', seed: 404, saved: true);
    expect(
      declared.applyTo(_spec.copyWith(player: const PlayerSpec(creative: true))).player.creative,
      isTrue,
      reason: 'no mode: as the game declares',
    );
  });

  test('the world list says how long and when', () {
    expect(WorldList.playTimeLabel(const Duration(seconds: 45)), '45 s');
    expect(WorldList.playTimeLabel(const Duration(minutes: 12, seconds: 5)), '12 min');
    expect(WorldList.playTimeLabel(const Duration(hours: 3, minutes: 5)), '3 h 05 min');
    expect(WorldList.dateLabel(DateTime(2026, 1, 2, 3, 4)), '2026-01-02 03:04');
    final w = WorldInfo(
      slot: 's',
      name: 'S',
      seed: 9,
      saved: true,
      mode: WorldMode.survival,
      lastPlayed: DateTime(2026, 10, 2, 14, 3),
      playTime: const Duration(minutes: 3),
    );
    expect(WorldList.detailsOf(w), 'Survival · seed 9 · played 3 min · last 2026-10-02 14:03');
    expect(WorldList.detailsOf(const WorldInfo(slot: 's', name: 'S', seed: 9, saved: false)), 'seed 9 · new');
  });

  group('WorldList', () {
    Future<List<String>> mount(WidgetTester tester, WorldSaves saves, {bool modes = true}) async {
      final played = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: WorldList(saves: saves, modes: modes, onPlay: played.add, onBack: () {}),
          ),
        ),
      );
      return played;
    }

    testWidgets('makes a world from a name, a seed of any text and a mode, and plays it', (tester) async {
      final (saves, _) = _saves();
      final played = await mount(tester, saves);
      expect(find.text('No worlds yet.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Play')).onPressed, isNull);

      await tester.tap(find.text('New world'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), '');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create')).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Island');
      await tester.enterText(find.widgetWithText(TextField, 'Seed'), 'hello');
      await tester.tap(find.text('Creative'));
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pump();

      expect(played, ['island']);
      final info = saves.info('island');
      expect(info.seed, 1335831723);
      expect(info.mode, WorldMode.creative);
    });

    testWidgets('a game with no modes makes worlds that play as it declares', (tester) async {
      final (saves, _) = _saves();
      await mount(tester, saves, modes: false);
      await tester.tap(find.text('New world'));
      await tester.pump();
      expect(find.text('Creative'), findsNothing);
      await tester.tap(find.text('Create'));
      await tester.pump();
      expect(saves.info('new_world').mode, isNull);
    });

    testWidgets('plays, renames and deletes the world selected', (tester) async {
      final (saves, at) = _saves();
      saves.create('Alpha', seed: 1);
      at(DateTime(2026, 10, 3));
      saves.create('Beta', seed: 2);
      final played = await mount(tester, saves);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('seed 2 · new'), findsOneWidget);

      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.tap(find.text('Play'));
      expect(played, ['alpha'], reason: 'the last made comes first, but the tap picked Alpha');

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Gamma');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Gamma'), findsOneWidget);
      expect(saves.info('alpha').name, 'Gamma');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text("Delete 'Gamma'? It is gone for good."), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(saves.list(), ['beta']);
      expect(find.text('Gamma'), findsNothing);
    });
  });

  group('TitleScreen', () {
    Future<List<TitleChoice>> mount(
      WidgetTester tester,
      WorldSaves saves,
      SettingsStore settings, {
      TitleSpec menu = const TitleSpec(name: 'Blocks'),
      VoidCallback? onQuit,
      String? status,
    }) async {
      final picked = <TitleChoice>[];
      await tester.pumpWidget(
        MaterialApp(
          home: TitleScreen(
            spec: _spec,
            menu: menu,
            saves: saves,
            settings: settings,
            onChoice: picked.add,
            onQuit: onQuit,
            status: status,
          ),
        ),
      );
      return picked;
    }

    SettingsStore store(WorldSaves saves) => SettingsStore(File('${saves.directory.path}/settings.json'));

    testWidgets('offers what the game declares', (tester) async {
      final (saves, _) = _saves();
      await mount(tester, saves, store(saves), status: 'Could not join x');
      expect(find.text('Blocks'), findsOneWidget);
      expect(find.text('Could not join x'), findsOneWidget);
      for (final b in ['Play', 'Multiplayer', 'Settings']) {
        expect(find.text(b), findsOneWidget);
      }
      expect(find.text('Credits'), findsNothing, reason: 'no credits declared');
      expect(find.text('Quit'), findsNothing, reason: 'nowhere to quit to');

      await mount(
        tester,
        saves,
        store(saves),
        menu: const TitleSpec(name: 'Blocks', tagline: 'a test', multiplayer: false, credits: ['Blocks', 'by us']),
        onQuit: () {},
      );
      expect(find.text('a test'), findsOneWidget);
      expect(find.text('Multiplayer'), findsNothing);
      await tester.tap(find.text('Credits'));
      await tester.pump();
      expect(find.text('by us'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Quit'), findsOneWidget);
    });

    testWidgets('Play opens the worlds, Escape the menu again, and a world played is picked', (tester) async {
      final (saves, _) = _saves();
      saves.create('Home', seed: 1);
      final picked = await mount(tester, saves, store(saves));
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(find.text('Worlds'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Worlds'), findsNothing);

      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Play'));
      expect(
        picked.single,
        isA<PlayWorld>().having((p) => p.slot, 'slot', 'home').having((p) => p.hostPort, 'port', null),
      );
    });

    testWidgets('the settings are the store\'s, read and written with no game', (tester) async {
      final (saves, _) = _saves();
      final settings = store(saves);
      settings.write(GameSettings.of(_spec).copyWith(showFps: true));
      await mount(tester, saves, settings);
      await tester.tap(find.text('Settings'));
      await tester.pump();
      final fps = find.widgetWithText(SwitchListTile, 'Show FPS');
      expect(tester.widget<SwitchListTile>(fps).value, isTrue);
      await tester.tap(fps);
      await tester.pump();
      expect(settings.read(GameSettings.of(_spec)).showFps, isTrue, reason: 'written once the change rests');
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(settings.read(GameSettings.of(_spec)).showFps, isFalse);
    });

    testWidgets('Multiplayer hosts a world of the list and joins an address', (tester) async {
      final (saves, _) = _saves();
      saves.create('Shared', seed: 1);
      final picked = await mount(tester, saves, store(saves), menu: const TitleSpec(name: 'Blocks', port: 4000));
      await tester.tap(find.text('Multiplayer'));
      await tester.pump();
      expect(find.text('Host a world on port 4000'), findsOneWidget);
      await tester.tap(find.text('Host'));
      expect(
        picked.last,
        isA<PlayWorld>().having((p) => p.slot, 'slot', 'shared').having((p) => p.hostPort, 'port', 4000),
      );

      Finder join() => find.widgetWithText(FilledButton, 'Join');
      expect(tester.widget<FilledButton>(join()).onPressed, isNull, reason: 'no address yet');
      await tester.enterText(find.widgetWithText(TextField, 'Address'), 'not an address!');
      await tester.pump();
      expect(tester.widget<FilledButton>(join()).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'Address'), '192.168.0.10');
      await tester.pump();
      await tester.tap(join());
      expect(picked.last, isA<JoinHost>().having((j) => j.address, 'address', '192.168.0.10:4000'));
      await tester.enterText(find.widgetWithText(TextField, 'Address'), 'lan-box:7000');
      await tester.pump();
      await tester.tap(join());
      expect(picked.last, isA<JoinHost>().having((j) => j.address, 'address', 'lan-box:7000'));
    });
  });

  test('runVoxelGame with a menu leaves the world to the title', () async {
    await expectLater(
      runVoxelGame(
        _spec,
        menu: const TitleSpec(name: 'x'),
        saveSlot: 'world1',
      ),
      throwsArgumentError,
    );
  });
}
