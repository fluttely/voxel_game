import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _music = MusicSpec(
  tracks: {
    'meadow': MusicTrack(score: StockMusic.pastoral, title: 'Meadow'),
    'dusk': MusicTrack(score: StockMusic.murky),
    'deep': MusicTrack(score: StockMusic.cavern, title: 'Deep'),
    'dunes': MusicTrack(asset: 'assets/music/dunes.mp3', score: StockMusic.arid),
    'fire': MusicTrack(score: StockMusic.infernal, title: 'Fire'),
  },
  day: 'meadow',
  cave: 'deep',
  biomes: {'sands': 'dunes'},
  dimensions: {'nether': 'fire'},
);

VoxelGameSpec _spec({MusicSpec? music = _music, bool sound = true}) => VoxelGameSpec(
  blocks: const [
    BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
    BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType('sand', color: 0xDBCB8E, hardness: 0.5, tool: 'shovel'),
    BlockType('netherrack', color: 0x6E2A2A, hardness: 0.4, tool: 'pickaxe'),
    BlockType.liquid('water', color: 0x3366CC),
  ],
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
    beach: Biome('sands', top: 'sand'),
  ),
  dimensions: const {
    'nether': WorldGenSpec(
      terrain: TerrainRecipe.flat(20),
      seaLevel: 5,
      stone: 'netherrack',
      caves: CaveSpec.none,
      biomes: [Biome('wastes', top: 'netherrack', precipitation: Precipitation.none)],
    ),
  },
  seed: 7,
  sky: SkySpec.alwaysDay,
  sounds: SoundSpec(enabled: sound, music: music),
);

Future<VoxelGame> _start(VoxelGameSpec spec) async {
  final game = await VoxelGame.startHeadless(spec);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
  return game;
}

Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

List<String> _told(VoxelGame game) => [for (final n in game.notices.feed) n.text];

void main() {
  group('MusicSpec.trackAt', () {
    String? at({String dimension = 'world', String biome = 'plains', bool underground = false, bool night = false}) =>
        _music.trackAt(dimension: dimension, biome: biome, underground: underground, night: night);

    test('the day\'s track by day, and by night when the night names none', () {
      expect(at(), 'meadow');
      expect(at(night: true), 'meadow');
    });

    test('a night of its own', () {
      const music = MusicSpec(
        tracks: {
          'a': MusicTrack(asset: 'a.mp3'),
          'b': MusicTrack(asset: 'b.mp3'),
        },
        day: 'a',
        night: 'b',
      );
      expect(music.trackAt(dimension: 'world', biome: 'plains', underground: false, night: true), 'b');
    });

    test('a biome\'s track day and night; the cave over it; the dimension over both', () {
      expect(at(biome: 'sands'), 'dunes');
      expect(at(biome: 'sands', night: true), 'dunes');
      expect(at(biome: 'sands', underground: true), 'deep');
      expect(at(dimension: 'nether', underground: true, night: true), 'fire');
    });

    test('silence where nothing names a track', () {
      const music = MusicSpec(
        tracks: {'a': MusicTrack(asset: 'a.mp3')},
        cave: 'a',
      );
      expect(music.trackAt(dimension: 'world', biome: 'plains', underground: false, night: false), isNull);
    });
  });

  group('a spec\'s music is checked', () {
    test('a place naming no track throws', () {
      expect(
        () => _spec(
          music: const MusicSpec(tracks: {}, day: 'meadow'),
        ).checkMusic(),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', 'no such track')),
      );
    });

    test('a biome no world has throws', () {
      expect(
        () => _spec(
          music: const MusicSpec(
            tracks: {'a': MusicTrack(asset: 'a.mp3')},
            biomes: {'moon': 'a'},
          ),
        ).checkMusic(),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', 'no such biome')),
      );
    });

    test('a dimension not declared throws', () {
      expect(
        () => _spec(
          music: const MusicSpec(
            tracks: {'a': MusicTrack(asset: 'a.mp3')},
            dimensions: {'moon': 'a'},
          ),
        ).checkMusic(),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', 'no such dimension')),
      );
    });

    test('a biome of another dimension, the ocean or the beach is one', () {
      const music = MusicSpec(
        tracks: {'a': MusicTrack(asset: 'a.mp3')},
        biomes: {'wastes': 'a', 'sands': 'a'},
      );
      _spec(music: music).checkMusic();
    });

    test('the game checks it when made', () async {
      await expectLater(
        VoxelGame.startHeadless(
          _spec(
            music: const MusicSpec(tracks: {}, cave: 'deep'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the game picks the track', () {
    test('none before the player stands, the day\'s once it does, told by its title', () async {
      final game = await _start(_spec());
      expect(game.musicTrack.value, isNull, reason: 'the step that stands the player picks nothing');
      await _run(game, 0.1);
      expect(game.musicTrack.value, 'meadow');
      expect(_told(game), ['♪ Meadow']);
    });

    test('the night keeps the day\'s track playing, and tells nothing', () async {
      final game = await _start(_spec());
      await _run(game, 0.1);
      var changes = 0;
      game.musicTrack.addListener(() => changes++);
      game.timeOfDay = 0.0;
      expect(game.daylight, lessThan(0.3));
      await _run(game, 2.0);
      expect(game.musicTrack.value, 'meadow');
      expect(changes, 0);
      expect(_told(game), ['♪ Meadow']);
    });

    test('underground, the cave\'s', () async {
      final game = await _start(_spec());
      final p = game.player.position;
      final deep = IVec3(p.x.floor(), 8, p.z.floor());
      for (final c in [deep, deep + IVec3.up]) {
        game.world.setBlockNamed(c, 'air');
      }
      game.player.placeAt(Vector3(deep.x + 0.5, deep.y.toDouble(), deep.z + 0.5));
      await _run(game, 1.2);
      expect(game.musicTrack.value, 'deep');
      expect(_told(game).last, '♪ Deep');
    });

    test('a dimension\'s own track', () async {
      final game = await _start(_spec());
      await _run(game, 0.1);
      game.travel('nether');
      for (var i = 0; i < 600 && game.travelState is Arriving; i++) {
        game.frame(1 / 60);
        await Future<void>.delayed(Duration.zero);
      }
      await _run(game, 1.2);
      expect(game.musicTrack.value, 'fire');
      expect(_told(game).last, '♪ Fire');
    });

    test('nothing with no music, or with the sound off', () async {
      for (final spec in [_spec(music: null), _spec(sound: false)]) {
        final game = await _start(spec);
        await _run(game, 1.2);
        expect(game.musicTrack.value, isNull);
        expect(_told(game), isEmpty);
      }
    });
  });

  testWidgets('the settings offer the music\'s volume only to a game that has music', (tester) async {
    Future<void> show(VoxelGameSpec spec) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsPanel(spec: spec, value: GameSettings.of(spec), onChanged: (_) {}),
          ),
        ),
      ),
    );
    await show(_spec());
    expect(find.text('Music'), findsOneWidget);
    await show(_spec(music: null));
    expect(find.text('Music'), findsNothing);
    await show(_spec(sound: false));
    expect(find.text('Music'), findsNothing);
  });
}
