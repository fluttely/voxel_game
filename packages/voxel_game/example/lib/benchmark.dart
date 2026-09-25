// The example game as a benchmark: a fixed world, a scripted camera, the frames
// measured, one JSON line printed, then exit. `tool/run_benchmark.dart` (from the
// repository's root) builds it in release and reads the line; by hand:
//
//   flutter build macos --release -t lib/benchmark.dart
//   build/macos/Build/Products/Release/voxel_game_example.app/Contents/MacOS/voxel_game_example \
//     --scenario=orbit --radius=6 --seconds=12 --window=1600x900
//
// A platform that cannot pass arguments (iOS, Android) takes the same flags in
// one define: `--dart-define=BENCH="--scenario=orbit --radius=6"`.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:voxel_game/voxel_game.dart';

import 'main.dart' as example;

/// What the camera does while the frames are measured.
enum Scenario {
  /// Hovers over the spawn and turns once around: the steady cost of a loaded
  /// window, every chunk of it in view once.
  orbit,

  /// Flies east at [Bench.flySpeed] over the terrain: the cost of streaming,
  /// chunks arriving and leaving every second.
  fly,

  /// As [orbit], lower, with [Bench.mobCount] creatures around the player,
  /// half of them hunting it: the cost of brains, paths, rigs and their shadows.
  mobs,
}

Future<void> main(List<String> args) async {
  const define = String.fromEnvironment('BENCH');
  final bench = Bench.parse([...args, ...define.split(' ').where((a) => a.isNotEmpty)]);
  WidgetsFlutterBinding.ensureInitialized();
  await VoxelGameWidget.loadResources();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: Scaffold(body: VoxelGameWidget(spec: bench.spec, onReady: bench.ready)),
  ));
}

/// One benchmark run: [scenario] at [radius] chunks, measured for [seconds].
class Bench {
  Bench(this.scenario, this.radius, this.seconds);

  /// Reads `--scenario=`, `--radius=` and `--seconds=` (the rest is the runner's).
  factory Bench.parse(List<String> args) {
    String arg(String name, String fallback) =>
        args.firstWhere((a) => a.startsWith('--$name='), orElse: () => '--$name=$fallback').split('=')[1];
    return Bench(Scenario.values.byName(arg('scenario', 'orbit')), int.parse(arg('radius', '6')), double.parse(arg('seconds', '12')));
  }

  final Scenario scenario;
  final int radius;
  final double seconds;

  /// Seconds after the window fills before the recording starts.
  static const double settle = 2.0;

  /// Metres per second east in [Scenario.fly]: a chunk a second.
  static const double flySpeed = 16.0;

  /// Creatures placed in [Scenario.mobs].
  static const int mobCount = 40;

  /// The window must fill within this, or the run fails.
  static const double fillTimeout = 90.0;

  late final VoxelGameSpec spec = example.game.copyWith(
    renderDistance: radius,
    // Creative: the hunters of the mobs run cannot end it by killing the player.
    player: PlayerSpec(creative: true, startingItems: example.game.player.startingItems),
    onTick: _tick,
  );

  final Stopwatch _clock = Stopwatch();
  _Phase _phase = _Phase.filling;
  double _phaseStart = 0.0;
  double? _fillMs;
  Vector3? _origin;
  Map<String, Object>? _world;

  void ready(VoxelGame game) {
    game.spawner.enabled = false;
    _clock.start();
  }

  double get _now => _clock.elapsedMicroseconds / 1e6;

  void _tick(VoxelGame game, double dt) {
    if (!game.ready) return;
    final origin = _origin ??= _start(game);
    final t = _phase == _Phase.measuring ? _now - _phaseStart : 0.0;
    _pose(game, origin, t);
    switch (_phase) {
      case _Phase.filling:
        final window = (2 * radius + 1) * (2 * radius + 1);
        if (game.world.meshCount >= window && game.world.isIdle) {
          _fillMs = _now * 1000.0;
          _world = {'chunks': game.world.meshCount, 'faces': game.world.facesEmitted, 'meshes': game.world.chunksBuilt};
          if (scenario == Scenario.mobs) _spawnMobs(game, origin);
          _enter(_Phase.settling);
        } else if (_now > fillTimeout) {
          stderr.writeln('[bench] the window did not fill in ${fillTimeout}s (${game.world.meshCount}/$window)');
          exit(1);
        }
      case _Phase.settling:
        if (_now - _phaseStart >= settle) {
          game.stats.startRecording();
          _enter(_Phase.measuring);
        }
      case _Phase.measuring:
        if (t >= seconds) _finish(game);
    }
  }

  void _enter(_Phase phase) {
    _phase = phase;
    _phaseStart = _now;
  }

  /// Where the camera hovers: over the spawn, high enough to see the window.
  Vector3 _start(VoxelGame game) {
    final p = game.player.position;
    final ground = game.world.groundHeight(p.x.floor(), p.z.floor()).toDouble();
    return Vector3(p.x, scenario == Scenario.mobs ? ground + 1.0 : ground + 16.0, p.z);
  }

  /// The player's pose [t] seconds into the recording, held at t = 0 before.
  void _pose(VoxelGame game, Vector3 origin, double t) {
    final player = game.player;
    player.velocity = Vector3.zero();
    switch (scenario) {
      case Scenario.orbit || Scenario.mobs:
        player.position.setFrom(origin);
        player.yaw = 2 * math.pi * t / seconds;
        player.pitch = scenario == Scenario.mobs ? -0.15 : -0.35;
      case Scenario.fly:
        player.position.setValues(origin.x + flySpeed * t, origin.y, origin.z);
        player.yaw = -math.pi / 2; // east
        player.pitch = -0.35;
    }
  }

  /// [mobCount] creatures on rings 6..14 m around [origin], alternating the
  /// example's species (a grazer and a hunter).
  void _spawnMobs(VoxelGame game, Vector3 origin) {
    final species = game.spec.mobs;
    for (var i = 0; i < mobCount; i++) {
      final a = i * 2 * math.pi / mobCount;
      final r = 6.0 + (i % 5) * 2.0;
      final x = origin.x + math.cos(a) * r, z = origin.z + math.sin(a) * r;
      final y = game.world.groundHeight(x.floor(), z.floor()) + 1.0;
      game.spawnMob(species[i % species.length].id, Vector3(x, y, z));
    }
  }

  void _finish(VoxelGame game) {
    final report = game.stats.stopRecording();
    final display = PlatformDispatcher.instance.displays.first;
    final view = PlatformDispatcher.instance.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    final line = {
      'scenario': scenario.name,
      'radius': radius,
      'platform': Platform.operatingSystem,
      'refreshHz': display.refreshRate,
      'window': '${size.width.round()}x${size.height.round()}',
      'dpr': view.devicePixelRatio,
      'fillMs': _fillMs!.round(),
      ...?_world,
      'mobs': game.mobs.length,
      ...report.toJson(1000.0 / display.refreshRate),
      'maxRssMb': (ProcessInfo.maxRss / (1 << 20)).round(),
    };
    stdout.writeln('[bench] ${jsonEncode(line)}');
    exit(0);
  }
}

enum _Phase { filling, settling, measuring }
