import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' show PerspectiveCamera;
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
  renderDistance: 8,
  player: PlayerSpec(fov: 80),
  sounds: SoundSpec(musicVolume: 0.3),
);

/// What was played, at what loudness.
class _Heard implements SoundPlayer {
  final List<(String, double)> played = [];

  @override
  void play(String name, {double volumeDb = 0.0, double pitch = 1.0}) => played.add((name, volumeDb));
}

Future<VoxelGame> _start() async {
  final game = await VoxelGame.startHeadless(_spec);
  game.spawner.enabled = false;
  await _fill(game);
  return game;
}

/// Frames until the window around the player is generated and meshed.
Future<void> _fill(VoxelGame game) async {
  for (var i = 0; i < 2000 && !game.filled; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.filled, isTrue, reason: 'the window fills');
}

void main() {
  group('GameSettings', () {
    test('the spec\'s values are the defaults', () {
      final s = GameSettings.of(_spec);
      expect(s.renderDistance, 8);
      expect(s.fov, 80);
      expect(s.musicVolume, 0.3);
      expect(s.lookSpeed, 1.0);
      expect(s.volume, 1.0);
      expect(s.viewBob, isTrue);
      expect(s.showFps, isFalse);
      expect(s.weather, isTrue);
      expect(s.game, isEmpty);
    });

    test('a value out of its range throws', () {
      final s = GameSettings.of(_spec);
      expect(() => s.copyWith(renderDistance: GameSettings.maxRenderDistance + 1), throwsArgumentError);
      expect(() => s.copyWith(renderDistance: GameSettings.minRenderDistance - 1), throwsArgumentError);
      expect(() => s.copyWith(lookSpeed: 0.0), throwsArgumentError);
      expect(() => s.copyWith(fov: 170), throwsArgumentError);
      expect(() => s.copyWith(volume: 1.5), throwsArgumentError);
      expect(() => s.copyWith(musicVolume: -0.1), throwsArgumentError);
      expect(() => s.copyWith(volume: double.nan), throwsArgumentError);
      expect(
        () => GameSettings.of(_spec.copyWith(renderDistance: 40)),
        throwsArgumentError,
        reason: 'a spec whose default is out of range is told so',
      );
    });

    test('JSON keeps every value, and refuses another version', () {
      final s = GameSettings.of(_spec).copyWith(
        renderDistance: 4,
        lookSpeed: 1.5,
        fov: 95,
        volume: 0.4,
        musicVolume: 0.9,
        viewBob: false,
        showFps: true,
        weather: false,
        game: {
          'tutorialDone': true,
          'keys': ['w', 'a'],
          'hint': {'seen': 2, 'at': 0.5},
        },
      );
      expect(s.toJson()['version'], 3);
      expect(GameSettings.fromJson(s.toJson()), s);
      expect(() => GameSettings.fromJson({...s.toJson(), 'version': 4}), throwsStateError);
      expect(() => GameSettings.fromJson({...s.toJson(), 'version': 0}), throwsStateError);
      expect(() => GameSettings.fromJson({...s.toJson()}..remove('fov')), throwsA(isA<TypeError>()));
      expect(() => GameSettings.fromJson({...s.toJson()}..remove('weather')), throwsA(isA<TypeError>()));
      expect(() => GameSettings.fromJson({...s.toJson()}..remove('game')), throwsA(isA<TypeError>()));
    });

    test('a version 2 file still loads, the game\'s own settings empty', () {
      final v2 = {...GameSettings.of(_spec).copyWith(fov: 95, weather: false).toJson(), 'version': 2}..remove('game');
      final s = GameSettings.fromJson(v2);
      expect(s.game, isEmpty);
      expect(s, GameSettings.of(_spec).copyWith(fov: 95, weather: false));
    });

    test('the game\'s own settings are a copy no one changes, of JSON alone, told apart by value', () {
      final given = <String, Object?>{
        'hint': {'seen': 1},
        'keys': ['w'],
      };
      final s = GameSettings.of(_spec).copyWith(game: given);
      (given['keys']! as List<Object?>).add('a');
      expect(s.game['keys'], ['w'], reason: 'copied, not kept');
      expect(() => s.game['more'] = 1, throwsUnsupportedError);
      expect(() => (s.game['hint']! as Map<String, Object?>)['seen'] = 2, throwsUnsupportedError);
      expect(() => (s.game['keys']! as List<Object?>).add('a'), throwsUnsupportedError);
      final same = GameSettings.of(_spec).copyWith(
        game: {
          'keys': ['w'],
          'hint': {'seen': 1},
        },
      );
      expect(same, s, reason: 'equal by value, nested too');
      expect(same.hashCode, s.hashCode);
      expect(
        GameSettings.of(_spec).copyWith(
          game: {
            'hint': {'seen': 2},
            'keys': ['w'],
          },
        ),
        isNot(s),
      );
      expect(s.copyWith(fov: 90).game, s.game, reason: 'a copy keeps them');
      expect(() => s.copyWith(game: {'at': DateTime(2026)}), throwsArgumentError);
      expect(() => s.copyWith(game: {'at': double.nan}), throwsArgumentError);
      expect(
        () => s.copyWith(
          game: {
            'deep': [
              {'x': Object()},
            ],
          },
        ),
        throwsArgumentError,
      );
    });

    test('a version 1 file still loads, the weather on', () {
      final v1 = {
        'version': 1,
        'renderDistance': 4,
        'lookSpeed': 1.5,
        'fov': 95,
        'volume': 0.4,
        'musicVolume': 0.9,
        'viewBob': false,
        'showFps': true,
      };
      final s = GameSettings.fromJson(v1);
      expect(s.weather, isTrue);
      expect(
        s,
        GameSettings.of(_spec).copyWith(
          renderDistance: 4,
          lookSpeed: 1.5,
          fov: 95,
          volume: 0.4,
          musicVolume: 0.9,
          viewBob: false,
          showFps: true,
        ),
      );
    });
  });

  group('SettingsStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('voxel_settings'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('before anything is kept it reads the defaults; then what was kept', () {
      final store = SettingsStore(File('${dir.path}/app/settings.json'));
      final defaults = GameSettings.of(_spec);
      expect(store.read(defaults), same(defaults));
      final mine = defaults.copyWith(fov: 100, showFps: true);
      store.write(mine);
      expect(store.read(defaults), mine);
      expect(File('${dir.path}/app/settings.json.tmp').existsSync(), isFalse, reason: 'written beside, renamed over');
    });

    test('the game\'s own settings are kept with the rest, and an older file reads none', () {
      final file = File('${dir.path}/settings.json');
      final store = SettingsStore(file);
      final defaults = GameSettings.of(_spec);
      final mine = defaults.copyWith(
        showFps: true,
        game: {
          'tutorialDone': true,
          'layout': {'jump': 'space'},
        },
      );
      store.write(mine);
      final read = store.read(defaults);
      expect(read, mine);
      expect(read.game['layout'], {'jump': 'space'});
      file.writeAsStringSync(
        '{"version":2,"renderDistance":4,"lookSpeed":1,"fov":70,'
        '"volume":1,"musicVolume":1,"viewBob":true,"showFps":false,"weather":true}',
      );
      expect(store.read(defaults).game, isEmpty);
    });

    test('a file out of range throws instead of loading the defaults', () {
      final file = File('${dir.path}/settings.json')
        ..writeAsStringSync(
          '{"version":1,"renderDistance":99,"lookSpeed":1,"fov":70,'
          '"volume":1,"musicVolume":1,"viewBob":true,"showFps":false}',
        );
      expect(() => SettingsStore(file).read(GameSettings.of(_spec)), throwsArgumentError);
    });
  });

  group('applied to a running game', () {
    test('a headless game\'s settings stream its load radius', () async {
      final game = await VoxelGame.startHeadless(_spec, loadRadius: 3);
      expect(game.settings.value.renderDistance, 3);
      expect(game.world.loadRadius, 3);
      game.dispose();
    });

    test('a headless game starts with the player\'s settings given, at its load radius', () async {
      final mine = GameSettings.of(_spec).copyWith(fov: 100, game: {'tutorialDone': true});
      final game = await VoxelGame.startHeadless(_spec, loadRadius: 3, settings: mine);
      expect(game.settings.value, mine.copyWith(renderDistance: 3));
      expect(game.settings.value.game['tutorialDone'], isTrue, reason: 'there before the first step');
      game.dispose();
    });

    test('the render distance streams further, and nearer, at once', () async {
      final game = await _start();
      final s = game.settings.value;
      expect(game.world.loadRadius, 2);
      game.applySettings(s.copyWith(renderDistance: 4));
      expect(game.world.loadRadius, 4);
      expect(game.viewDistance, 64.0, reason: 'the fog and the far plane follow');
      game.frame(1 / 60);
      expect(game.filled, isFalse, reason: 'the wider window has chunks to stream');
      await _fill(game);
      game.applySettings(game.settings.value.copyWith(renderDistance: 2));
      game.frame(1 / 60);
      expect(game.filled, isTrue, reason: 'a nearer window has nothing to wait for');
      expect(game.viewDistance, 32.0);
      game.dispose();
    });

    test('the look speed scales the turn; the camera takes the field of view; the bob follows', () async {
      final game = await _start();
      final p = game.player;
      game.applySettings(game.settings.value.copyWith(lookSpeed: 2.0, fov: 60, viewBob: false));
      final yaw = p.yaw;
      game.input.look(-10, 0);
      game.frame(1 / 480);
      expect(p.yaw, closeTo(yaw + 20 * game.input.lookSensitivity, 1e-9));
      expect((game.camera() as PerspectiveCamera).fovRadiansY, closeTo(60 * math.pi / 180, 1e-9));
      expect(game.view.bob, isFalse);
      game.dispose();
    });

    test('every sound plays under the volume, and none at 0', () async {
      final game = await _start();
      final heard = _Heard();
      game.sounds = heard;
      game.playSound('click');
      game.applySettings(game.settings.value.copyWith(volume: 0.5));
      game.playSound('click', volumeDb: -4);
      game.applySettings(game.settings.value.copyWith(volume: 0.0));
      game.playSound('click');
      expect(heard.played, hasLength(2));
      expect(heard.played[0].$2, 0.0);
      expect(heard.played[1].$2, closeTo(-4 - 6.0206, 1e-3));
      game.dispose();
    });

    test('a change is told to whoever listens', () async {
      final game = await _start();
      final seen = <GameSettings>[];
      game.settings.addListener(() => seen.add(game.settings.value));
      final next = game.settings.value.copyWith(musicVolume: 0.8);
      game.applySettings(next);
      expect(seen, [next]);
      game.dispose();
    });
  });
}
