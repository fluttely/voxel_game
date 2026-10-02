import 'dart:math' as math;

import 'package:voxel_engine/worldgen.dart' show Biome, Precipitation, WorldGenSpec;

import '../core/voxel_game.dart';
import '../spec/weather_spec.dart';
import 'weather_kind.dart';

/// The weather as it stands: the sky's [spell] (clear, rain or a storm),
/// rolled from [WeatherSpec]'s odds every few minutes where the game decides,
/// eased in and out over `WeatherSpec.fadeSeconds`, and what it does where
/// the player stands ([kind]): rain, a storm, snow where the biome's
/// precipitation is snow, nothing where it is none.
///
/// `VoxelGame.step` ticks it; `VoxelGame.frame` lights the sky by [overcast]
/// and [flash] and lets the rain and snow fall by [rainShare] and
/// [snowShare]. With no [spec] the sky stays clear.
class Weather {
  /// The weather of [spec] over [world]'s biomes, rolled by [seed]'s own
  /// random numbers. Throws [ArgumentError] for odds of a biome the world
  /// does not have.
  Weather(this.spec, WorldGenSpec world, {required int seed}) : _random = math.Random(seed ^ 0x57EA7E) {
    final s = spec;
    if (s == null) return;
    final names = {
      for (final b in <Biome>[...world.biomes, ?world.ocean, ?world.beach]) b.name,
    };
    for (final name in s.biomes.keys) {
      if (!names.contains(name)) throw ArgumentError.value(name, 'biomes', 'the world has no such biome');
    }
    _spellLeft = _spellLength(s);
  }

  /// What was declared, or null for a sky that is always clear.
  final WeatherSpec? spec;

  final math.Random _random;

  /// The sky's own weather, wherever the player stands: [WeatherKind.clear],
  /// [WeatherKind.rain] or [WeatherKind.storm].
  WeatherKind get spell => _spell;
  WeatherKind _spell = WeatherKind.clear;

  /// The last rain or storm, which keeps falling while it fades out.
  WeatherKind _wet = WeatherKind.rain;

  /// What the weather does where the player stands: clear once nothing
  /// falls, else the biome's precipitation of the last rain or storm.
  WeatherKind get kind {
    if (_intensity == 0.0) return WeatherKind.clear;
    return switch (_precipitation) {
      Precipitation.rain => _wet,
      Precipitation.snow => WeatherKind.snow,
      Precipitation.none => WeatherKind.clear,
    };
  }

  Precipitation _precipitation = Precipitation.rain;

  /// How hard it falls, 0 (nothing) .. 1, eased toward the spell's.
  double get intensity => _intensity;
  double _intensity = 0.0;
  double _target = 0.0;

  /// How much cloud hides the sky, 0 clear .. 0.75 a full storm: [intensity]
  /// times the last rain's darkness (0.45, snow too) or a storm's (0.75),
  /// eased from one to the other.
  double get overcast => _intensity * _darkness;
  double _darkness = _darknessOf(WeatherKind.rain);

  /// A bolt's light, 1 as it strikes and gone in a sixth of a second.
  double get flash => _flash;
  double _flash = 0.0;

  /// The share of the full rain falling, 0..1.
  double get rainShare => switch (kind) {
    WeatherKind.rain || WeatherKind.storm => _intensity,
    WeatherKind.clear || WeatherKind.snow => 0.0,
  };

  /// The share of the full snow falling, 0..1.
  double get snowShare => kind == WeatherKind.snow ? _intensity : 0.0;

  double _spellLeft = 0.0;
  double _nextBolt = 0.0;
  double _biomeLeft = 0.0;
  String _biome = '';

  /// Whether the player lets the weather turn (`GameSettings.weather`).
  /// Turned off, the sky clears at once and holds until it is turned on,
  /// when the next roll comes within half a minute.
  bool get enabled => _enabled;
  bool _enabled = true;
  set enabled(bool on) {
    if (on == _enabled) return;
    _enabled = on;
    if (!on) {
      _spell = WeatherKind.clear;
      _target = _intensity = _flash = 0.0;
    } else {
      _spellLeft = math.min(_spellLeft, 30.0);
    }
  }

  /// Starts a spell of [spell] now, falling at [intensity] (0..1, 0 for a
  /// clear sky), eased in, or at once with [now]; it lasts as a rolled one
  /// does. Throws [StateError] with no [spec] or the weather turned off, and
  /// [ArgumentError] for snow (a biome's, not a sky's) or an intensity out of
  /// its range.
  void set(WeatherKind spell, {double intensity = 1.0, bool now = false}) {
    final s = spec;
    if (s == null) throw StateError('the spec declares no weather');
    if (!_enabled) throw StateError('the player turned the weather off');
    if (spell == WeatherKind.snow) throw ArgumentError.value(spell, 'spell', 'snow is what a biome makes of rain');
    if (spell == WeatherKind.clear) intensity = 0.0;
    if (!(intensity >= 0.0 && intensity <= 1.0)) throw ArgumentError.value(intensity, 'intensity', 'not in 0..1');
    if (spell != WeatherKind.clear && intensity == 0.0) {
      throw ArgumentError.value(intensity, 'intensity', 'a rain that falls not at all');
    }
    _begin(s, spell, intensity);
    if (now) {
      _intensity = _target;
      _darkness = _darknessOf(_wet);
    }
  }

  /// One step of [dt] seconds in [game]: where it decides, the spell runs
  /// out and the next is rolled at the player's biome; everywhere, the
  /// weather eases toward the spell, follows the biome underfoot, and a
  /// storm strikes now and then.
  void tick(VoxelGame game, double dt) {
    final s = spec;
    if (s == null || !_enabled) return;
    _biomeLeft -= dt;
    if (_biomeLeft <= 0.0) {
      _biomeLeft = 0.25;
      final p = game.player.position;
      final b = game.world.generator.biomeAt(p.x.floor(), p.z.floor());
      _biome = b.name;
      _precipitation = b.precipitation;
    }
    if (game.authority) {
      _spellLeft -= dt;
      if (_spellLeft <= 0.0) _roll(s);
    }
    final rate = dt / s.fadeSeconds;
    _intensity = _toward(_intensity, _target, rate);
    _darkness = _toward(_darkness, _darknessOf(_wet), rate);
    _flash = math.max(_flash - dt * 6.0, 0.0);
    if (kind == WeatherKind.storm && _spell == WeatherKind.storm && _intensity > 0.5) {
      _nextBolt -= dt;
      if (_nextBolt <= 0.0) {
        _nextBolt = _between(s.minBolt, s.maxBolt);
        _flash = 1.0;
        game.playSound(s.thunder, volumeDb: -4.0, pitch: 0.7 + _random.nextDouble() * 0.4);
      }
    }
  }

  void _roll(WeatherSpec s) {
    final odds = s.biomes[_biome] ?? s.odds;
    final r = _random.nextDouble() * (odds.clear + odds.rain + odds.storm);
    if (r < odds.clear) {
      _begin(s, WeatherKind.clear, 0.0);
    } else if (r < odds.clear + odds.rain) {
      _begin(s, WeatherKind.rain, _between(0.5, 1.0));
    } else {
      _begin(s, WeatherKind.storm, 1.0);
    }
  }

  void _begin(WeatherSpec s, WeatherKind spell, double intensity) {
    // A storm rolled again goes on striking on its own clock.
    if (spell == WeatherKind.storm && _spell != WeatherKind.storm) _nextBolt = _between(s.minBolt, s.maxBolt);
    _spell = spell;
    _target = intensity;
    _spellLeft = _spellLength(s);
    if (spell != WeatherKind.clear) _wet = spell;
  }

  double _spellLength(WeatherSpec s) => _between(s.minSpell, s.maxSpell);

  double _between(double min, double max) => min + _random.nextDouble() * (max - min);

  /// How much a full rain or storm hides the sky.
  static double _darknessOf(WeatherKind wet) => switch (wet) {
    WeatherKind.storm => 0.75,
    WeatherKind.rain || WeatherKind.snow || WeatherKind.clear => 0.45,
  };

  static double _toward(double from, double to, double delta) {
    if ((to - from).abs() <= delta) return to;
    return from + (to > from ? delta : -delta);
  }
}
