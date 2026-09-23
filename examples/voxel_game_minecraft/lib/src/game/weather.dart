import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' hide Spawner;
import 'package:flutter_scene/scene.dart' as fs show Spawner;
import 'package:vector_math/vector_math.dart';

import '../world/voxel_world.dart';
import 'net.dart';
import 'sfx.dart';

enum WeatherKind { clear, rain, storm, snow }

/// Weather: clear, rain, storm or snow, rolled every few minutes and driven by
/// the biome the player stands in (deserts stay dry, cold biomes get snow).
/// Particles follow the player; the sky darkens through [darken], which the sun
/// and the fog read every frame. A storm adds lightning: a sky flash and a
/// rumble. Rain puts out a burning player and waters crops.
class Weather {
  Weather(this._player, this._world) {
    _rain = _emitter(
      size: 0.55,
      aspect: 0.04 / 0.55,
      color: Vector4(0.65, 0.75, 0.95, 0.55),
      fallSpeed: 16.0,
      amount: 900,
      facing: BillboardFacing.velocityStretched,
    );
    _snow = _emitter(
      size: 0.12,
      aspect: 1.0,
      color: Vector4(0.95, 0.96, 1.0, 0.9),
      fallSpeed: 2.0,
      amount: 500,
      facing: BillboardFacing.spherical,
    );
    _rainRate = _rain.system.spawner.rate;
    _snowRate = _snow.system.spawner.rate;
    node.add(_rainNode..addComponent(_rain));
    node.add(_snowNode..addComponent(_snow));
    _rainNode.visible = false;
    _snowNode.visible = false;
  }

  final Node node = Node(name: 'Weather');
  final Node _rainNode = Node(name: 'Rain');
  final Node _snowNode = Node(name: 'Snow');
  final Vector3 Function() _player;
  final VoxelWorld _world;
  final math.Random _rng = math.Random();

  WeatherKind kind = WeatherKind.clear;

  /// 0..1, eased so the sky changes over a few seconds.
  double intensity = 0.0;
  double _target = 0.0;
  double _timer = 120.0;
  double _flash = 0.0;
  double _nextBolt = 0.0;

  /// Set by a probe flag or, on a client, by the host's roll: the local timer
  /// stops rolling on its own.
  bool forced = false;

  /// Stage 24: the settings switch. Off forces clear and holds it until
  /// switched back on.
  bool enabled = true;

  /// Stage 29: the underworld has no sky. While suppressed the weather is clear
  /// and hidden, whatever the switch or the host says; back in the overworld the
  /// timer rolls again.
  bool suppressed = false;

  void setEnabled(bool on) {
    enabled = on;
    if (!on) {
      kind = WeatherKind.clear;
      _target = 0.0;
      intensity = 0.0;
    } else if (!forced) {
      _timer = math.min(_timer, 30.0);
    }
  }

  /// Stage 21b: the host tells clients what it rolled; every 10 s and on change.
  double _syncTimer = 0.0;
  WeatherKind? _sentKind;
  double _sentTarget = -1.0;

  late final ParticleEmitterComponent _rain;
  late final ParticleEmitterComponent _snow;
  late final double _rainRate;
  late final double _snowRate;

  ParticleEmitterComponent _emitter({
    required double size,
    required double aspect,
    required Vector4 color,
    required double fallSpeed,
    required int amount,
    required BillboardFacing facing,
  }) {
    final lifetime = 34.0 / fallSpeed;
    final system = ParticleSystem(
      maxParticles: amount,
      shape: BoxEmitterShape(
        halfExtents: Vector3(26.0, 1.0, 26.0),
        direction: Vector3(0.15, -1.0, 0.0),
      ),
      spawner: fs.Spawner(rate: amount / lifetime),
      lifetime: ConstantFloat(lifetime),
      startSpeed: UniformFloat(fallSpeed * 0.8, fallSpeed * 1.2),
      startSize: ConstantFloat(size),
      startColor: ConstantColor(color),
    );
    final material = SpriteMaterial()..blendMode = SpriteBlendMode.alpha;
    final emitter = ParticleEmitterComponent(system: system, material: material)
      ..facing = facing
      ..aspectRatio = aspect;
    return emitter;
  }

  /// A probe flag or the pause menu forcing one kind on.
  void force(String name) {
    forced = true;
    kind = const {
      'clear': WeatherKind.clear,
      'rain': WeatherKind.rain,
      'storm': WeatherKind.storm,
      'snow': WeatherKind.snow,
    }[name]!;
    _target = kind == WeatherKind.clear ? 0.0 : 1.0;
    intensity = _target;
  }

  double get target => _target;

  /// Client: follow the host's roll. [forced] stops the local timer from rolling
  /// on its own.
  void follow(WeatherKind newKind, double newTarget) {
    forced = true;
    kind = newKind;
    _target = newTarget;
  }

  static const List<String> labels = ['Clear', 'Rain', 'Storm', 'Snow'];

  String get label => labels[kind.index];

  bool get isWet => (kind == WeatherKind.rain || kind == WeatherKind.storm) && intensity > 0.3;

  /// 0 (clear) .. 1 (full storm): how much the sun and the ambient light lose.
  double darken() => intensity * (kind == WeatherKind.storm ? 0.75 : 0.45);

  double get flash => _flash;

  bool _coldHere() {
    final p = _player();
    final b = _world.biomeAt(p.x.toInt(), p.z.toInt());
    return b == 5 || b == 6;
  }

  bool _dryHere() {
    final p = _player();
    return _world.biomeAt(p.x.toInt(), p.z.toInt()) == 4;
  }

  void process(double dt) {
    if (!enabled || suppressed) {
      kind = WeatherKind.clear;
      _target = 0.0;
      intensity = 0.0;
    } else if (!forced) {
      _timer -= dt;
      if (_timer <= 0.0) _roll();
    }
    if (Net.instance.isHost) {
      _syncTimer -= dt;
      if (_syncTimer <= 0.0 || _sentKind != kind || _sentTarget != _target) {
        _syncTimer = 10.0;
        _sentKind = kind;
        _sentTarget = _target;
        Net.instance.broadcastWeather(kind, _target);
      }
    }
    // Snow and rain swap with the biome, so a walk into the mountains turns
    // the rain white.
    if (kind != WeatherKind.clear && _coldHere() && kind != WeatherKind.snow) {
      kind = WeatherKind.snow;
    } else if (kind == WeatherKind.snow && !_coldHere()) {
      kind = WeatherKind.rain;
    }
    intensity = _moveToward(intensity, _target, dt * 0.25);
    node.position = _player() + Vector3(0, 18.0, 0);
    final raining = intensity > 0.05 && (kind == WeatherKind.rain || kind == WeatherKind.storm);
    final snowing = intensity > 0.05 && kind == WeatherKind.snow;
    _rainNode.visible = raining;
    _snowNode.visible = snowing;
    _rain.system.spawner.rate = raining ? _rainRate * intensity : 0.0;
    _snow.system.spawner.rate = snowing ? _snowRate * intensity : 0.0;
    _flash = math.max(_flash - dt * 6.0, 0.0);
    if (kind == WeatherKind.storm && intensity > 0.5) {
      _nextBolt -= dt;
      if (_nextBolt <= 0.0) {
        _nextBolt = 4.0 + _rng.nextDouble() * 10.0;
        _flash = 1.0;
        Sfx.play('thunder', -4.0, 0.7 + _rng.nextDouble() * 0.4);
      }
    }
  }

  static double _moveToward(double from, double to, double delta) {
    if ((to - from).abs() <= delta) return to;
    return from + (to > from ? delta : -delta);
  }

  void _roll() {
    _timer = 90.0 + _rng.nextDouble() * 150.0;
    final r = _rng.nextDouble();
    if (_dryHere() || r < 0.55) {
      kind = WeatherKind.clear;
      _target = 0.0;
    } else if (r < 0.85) {
      kind = _coldHere() ? WeatherKind.snow : WeatherKind.rain;
      _target = 0.5 + _rng.nextDouble() * 0.5;
    } else {
      kind = _coldHere() ? WeatherKind.snow : WeatherKind.storm;
      _target = 1.0;
    }
  }
}
