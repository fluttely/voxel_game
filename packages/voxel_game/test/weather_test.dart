import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

/// A storm every time, rolled after a second, in over a [WeatherSpec.fadeSeconds] of 4.
const _storms = WeatherSpec(odds: WeatherOdds(clear: 0, rain: 0, storm: 1), minSpell: 1, maxSpell: 1);

VoxelGameSpec _spec({WeatherSpec? weather = _storms, Biome biome = const Biome('plains', top: 'grass')}) =>
    VoxelGameSpec(
      blocks: const [
        BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
        BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel'),
        BlockType('snow', color: 0xF0F0F0, hardness: 0.2, tool: 'shovel'),
        BlockType('sand', color: 0xDCCB8A, hardness: 0.5, tool: 'shovel'),
        BlockType.liquid('water', color: 0x3366CC),
      ],
      world: WorldGenSpec(terrain: const TerrainRecipe.flat(20), seaLevel: 5, caves: CaveSpec.none, biomes: [biome]),
      sky: SkySpec(weather: weather),
    );

/// What was played.
class _Heard implements SoundPlayer {
  final List<String> played = [];

  @override
  void play(String name, {double volumeDb = 0.0, double pitch = 1.0}) => played.add(name);
}

Future<VoxelGame> _start(VoxelGameSpec spec, {bool authority = true}) async {
  final game = await VoxelGame.startHeadless(spec, authority: authority);
  game.spawner.enabled = false;
  for (var i = 0; i < 2000 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue, reason: 'the player stands in the world');
  return game;
}

void _run(VoxelGame game, double seconds) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    game.step(1 / 60);
  }
}

void main() {
  test('with no weather declared the sky stays clear, and none can be set', () async {
    final game = await _start(_spec(weather: null));
    _run(game, 600);
    expect(game.weather.kind, WeatherKind.clear);
    expect(game.weather.overcast, 0.0);
    expect(() => game.weather.set(WeatherKind.rain), throwsStateError);
    game.dispose();
  });

  test('a storm is rolled, comes in over the fade, darkens the sky and strikes', () async {
    final game = await _start(_spec());
    final heard = _Heard();
    game.sounds = heard;
    final w = game.weather;
    expect(w.kind, WeatherKind.clear);
    _run(game, 1.1);
    expect(w.spell, WeatherKind.storm);
    expect(w.intensity, closeTo(0.1 / 4, 0.01), reason: 'eased in, a quarter a second');
    _run(game, 4);
    expect(w.kind, WeatherKind.storm);
    expect(w.intensity, 1.0);
    expect(w.overcast, closeTo(0.75, 1e-9));
    expect(w.rainShare, 1.0);
    expect(w.snowShare, 0.0);
    var flashed = false;
    for (var i = 0; i < 20 * 60; i++) {
      game.step(1 / 60);
      flashed |= w.flash > 0.0;
    }
    expect(flashed, isTrue, reason: 'a bolt every 4 to 14 s');
    expect(heard.played, contains('thunder'));
    game.dispose();
  });

  test('what falls is the biome\'s: snow where it snows, nothing in a desert', () async {
    final tundra = await _start(
      _spec(
        biome: const Biome('tundra', top: 'snow', precipitation: Precipitation.snow),
      ),
    );
    final heard = _Heard();
    tundra.sounds = heard;
    _run(tundra, 20);
    expect(tundra.weather.spell, WeatherKind.storm);
    expect(tundra.weather.kind, WeatherKind.snow);
    expect(tundra.weather.snowShare, 1.0);
    expect(tundra.weather.rainShare, 0.0);
    expect(tundra.weather.flash, 0.0);
    expect(heard.played, isNot(contains('thunder')), reason: 'a blizzard, not a thunderstorm');
    tundra.dispose();

    final desert = await _start(
      _spec(
        biome: const Biome('desert', top: 'sand', precipitation: Precipitation.none),
      ),
    );
    _run(desert, 6);
    expect(desert.weather.spell, WeatherKind.storm);
    expect(desert.weather.kind, WeatherKind.clear);
    expect(desert.weather.rainShare + desert.weather.snowShare, 0.0);
    expect(desert.weather.overcast, closeTo(0.75, 1e-9), reason: 'the sky greys over it all the same');
    desert.dispose();
  });

  test('a biome\'s own odds win over the spec\'s; a biome the world lacks throws', () async {
    final game = await _start(
      _spec(
        weather: const WeatherSpec(
          odds: WeatherOdds(clear: 0, rain: 0, storm: 1),
          biomes: {'plains': WeatherOdds.alwaysClear},
          minSpell: 1,
          maxSpell: 1,
        ),
      ),
    );
    _run(game, 30);
    expect(game.weather.kind, WeatherKind.clear);
    game.dispose();
    expect(
      () => VoxelGame.startHeadless(_spec(weather: const WeatherSpec(biomes: {'jungle': WeatherOdds()}))),
      throwsArgumentError,
    );
  });

  test('set starts a spell eased in, or at once; snow is not a sky\'s', () async {
    final game = await _start(_spec(weather: const WeatherSpec(odds: WeatherOdds.alwaysClear)));
    final w = game.weather;
    w.set(WeatherKind.rain, intensity: 0.8);
    _run(game, 2);
    expect(w.intensity, closeTo(0.5, 1e-6));
    expect(w.kind, WeatherKind.rain);
    expect(w.overcast, closeTo(0.45 * 0.5, 1e-6));
    w.set(WeatherKind.clear, now: true);
    expect(w.intensity, 0.0);
    expect(w.kind, WeatherKind.clear);
    expect(() => w.set(WeatherKind.snow), throwsArgumentError);
    expect(() => w.set(WeatherKind.rain, intensity: 0.0), throwsArgumentError);
    expect(() => w.set(WeatherKind.rain, intensity: 1.5), throwsArgumentError);
    game.dispose();
  });

  test('the player\'s switch clears the sky at once and holds it; back on, it rolls again', () async {
    final game = await _start(_spec());
    final w = game.weather;
    w.set(WeatherKind.storm, now: true);
    expect(w.overcast, 0.75);
    game.applySettings(game.settings.value.copyWith(weather: false));
    expect(w.enabled, isFalse);
    expect(w.kind, WeatherKind.clear);
    expect(w.overcast, 0.0);
    _run(game, 300);
    expect(w.kind, WeatherKind.clear, reason: 'held off for as long as it is off');
    expect(() => w.set(WeatherKind.rain), throwsStateError);
    game.applySettings(game.settings.value.copyWith(weather: true));
    _run(game, 6);
    expect(w.kind, WeatherKind.storm, reason: 'the next roll comes within half a minute (here a second)');
    game.dispose();
  });

  test('a client rolls nothing: the host decides', () async {
    final game = await _start(_spec(), authority: false);
    _run(game, 30);
    expect(game.weather.kind, WeatherKind.clear);
    game.dispose();
  });

  testWidgets('the settings offer the weather only to a game that has some', (tester) async {
    final rainy = _spec();
    var value = GameSettings.of(rainy);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) =>
                  SettingsPanel(spec: rainy, value: value, onChanged: (next) => setState(() => value = next)),
            ),
          ),
        ),
      ),
    );
    final weather = find.widgetWithText(SwitchListTile, 'Weather');
    expect(tester.widget<SwitchListTile>(weather).value, isTrue);
    await tester.tap(weather);
    await tester.pump();
    expect(value.weather, isFalse);

    final dry = _spec(weather: null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsPanel(spec: dry, value: GameSettings.of(dry), onChanged: (_) {}),
          ),
        ),
      ),
    );
    expect(find.text('Weather'), findsNothing);
  });
}
