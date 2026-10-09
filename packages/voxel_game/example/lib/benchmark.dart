// The example game as a benchmark: a fixed world, a scripted camera, the frames
// measured, one JSON line printed, then exit. `tool/run_benchmark.dart` (from the
// repository's root) builds it in release and reads the line; by hand:
//
//   flutter build macos --release -t lib/benchmark.dart
//   build/macos/Build/Products/Release/voxel_game_example.app/Contents/MacOS/voxel_game_example \
//     --scenario=orbit --radius=6 --seconds=12 --window=1600x900
//
// Android takes them in the launch intent, which is how `--android` runs it:
//
//   adb shell am start -S -n com.remottely.voxel_game_example/.MainActivity \
//     --esal dart_entrypoint_args --scenario=orbit,--radius=6
//
// iOS, which cannot pass arguments, takes the same flags in one define:
// `--dart-define=BENCH="--scenario=orbit --radius=6"`. A phone runs in
// landscape and full screen, the way the game is played.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome, SystemUiMode;
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:voxel_game/voxel_game.dart';

import 'main.dart' as example;

/// What the camera does while the frames are measured.
enum Scenario {
  /// Hovers over the spawn and turns once around: the steady cost of a loaded
  /// window, every chunk of it in view once. The view is turned by the look,
  /// at a steady rate, as a held stick turns it.
  orbit,

  /// Flies east at [Bench.flySpeed] over the terrain: the cost of streaming,
  /// chunks arriving and leaving every second. The player is moved by the
  /// game's clock, a step at a time, as a walk moves it.
  fly,

  /// As [orbit], lower, with [Bench.mobCount] creatures around the player,
  /// half of them hunting it: the cost of brains, paths, rigs and their shadows.
  mobs,
}

Future<void> main(List<String> args) async {
  const define = String.fromEnvironment('BENCH');
  final bench = Bench.parse([...args, ...define.split(' ').where((a) => a.isNotEmpty)]);
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await VoxelGameWidget.loadResources();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: VoxelGameWidget(spec: bench.spec, onReady: bench.ready),
      ),
    ),
  );
}

/// One benchmark run: [scenario] at [radius] chunks, measured for [seconds],
/// drawn with [graphics].
class Bench {
  Bench(this.scenario, this.radius, this.seconds, this.graphics, {this.peers = 0, this.edits = 0, this.aim = false});

  /// Reads `--scenario=`, `--radius=`, `--seconds=` and the look: `--graphics=`
  /// (`desktop` or `phone`, the base), then `--scale=`, `--max-ratio=`,
  /// `--aa=` (an `AntiAliasingMode`), `--shadows=` (`off`, or
  /// `cascades:resolution:distance`) and `--sun-step=` over it; then the
  /// network's load, `--peers=` and `--edits=`; then `--aim`. The rest is the
  /// runner's.
  factory Bench.parse(List<String> args) {
    String? arg(String name) =>
        args.where((a) => a.startsWith('--$name=')).map((a) => a.substring(name.length + 3)).lastOrNull;
    final base = switch (arg('graphics') ?? 'desktop') {
      'desktop' => GraphicsSpec.desktop,
      'phone' => GraphicsSpec.phone,
      final other => throw ArgumentError('--graphics=$other: desktop or phone'),
    };
    final shadowArg = arg('shadows'), sunStep = arg('sun-step');
    final parts = shadowArg?.split(':');
    final ShadowSpec shadows = switch (parts) {
      null => base.shadows,
      ['off'] => ShadowSpec.off,
      [final c, final r, final d] => ShadowSpec(
        cascades: int.parse(c),
        resolution: int.parse(r),
        distance: double.parse(d),
      ),
      _ => throw ArgumentError('--shadows=$shadowArg: off or cascades:resolution:distance'),
    };
    final maxRatio = arg('max-ratio');
    final graphics = GraphicsSpec(
      renderScale: double.parse(arg('scale') ?? '${base.renderScale}'),
      maxPixelRatio: maxRatio == null ? base.maxPixelRatio : double.parse(maxRatio),
      antiAliasing: arg('aa') == null ? base.antiAliasing : AntiAliasingMode.values.byName(arg('aa')!),
      shadows: sunStep == null
          ? shadows
          : ShadowSpec(
              enabled: shadows.enabled,
              cascades: shadows.cascades,
              resolution: shadows.resolution,
              distance: shadows.distance,
              sunStepDegrees: double.parse(sunStep),
            ),
    );
    final scenario = Scenario.values.byName(arg('scenario') ?? 'orbit');
    if (scenario == Scenario.fly && arg('edits') != null) {
      throw ArgumentError('--edits edits cells near the spawn, which fly leaves behind');
    }
    return Bench(
      scenario,
      int.parse(arg('radius') ?? '6'),
      double.parse(arg('seconds') ?? '12'),
      graphics,
      peers: int.parse(arg('peers') ?? '0'),
      edits: int.parse(arg('edits') ?? '0'),
      aim: args.contains('--aim'),
    );
  }

  final Scenario scenario;
  final int radius;
  final double seconds;
  final GraphicsSpec graphics;

  /// Scripted peers joined to the game, hosted once the window fills: each
  /// drains what the host sends and sends its pose [Bench.poseHz] times a
  /// second. 0 plays alone.
  final int peers;

  /// Cells edited in one step, every second of the recording: a cube of
  /// leaves near the spawn, set and cleared in turn, as an explosion edits
  /// a crater in one step. 0 edits nothing.
  final int edits;

  /// Whether the crosshair rests on a block the whole recording, so the
  /// selection outline is drawn: the player's reach is [aimReach], far enough
  /// for the look to meet the terrain from the hover's height and pitch, across
  /// valleys and water. The line gains `aimed`, the share of the recorded steps
  /// whose outline was shown.
  final bool aim;

  /// The player's reach under [aim], metres.
  static const double aimReach = 160.0;

  /// Seconds after the window fills before the recording starts.
  static const double settle = 2.0;

  /// Metres per second east in [Scenario.fly]: a chunk a second.
  static const double flySpeed = 16.0;

  /// Creatures placed in [Scenario.mobs].
  static const int mobCount = 40;

  /// The window must fill within this, or the run fails.
  static const double fillTimeout = 90.0;

  /// The peers must all have joined within this after the window fills, or
  /// the run fails.
  static const double joinTimeout = 10.0;

  /// A scripted peer's poses a second, as a client's session sends them.
  static const int poseHz = 20;

  late final VoxelGameSpec spec = example.game.copyWith(
    renderDistance: radius,
    graphics: () => graphics,
    // Creative: the hunters of the mobs run cannot end it by killing the player.
    player: PlayerSpec(
      creative: true,
      startingItems: example.game.player.startingItems,
      reach: aim ? aimReach : example.game.player.reach,
      // The example's creatures are worth experience, which a spec checks the player gains.
      xp: example.game.player.xp,
    ),
    systems: () => [...example.game.systems(), _Driver(_tick)],
    // The example's day with no weather: a storm rolled mid-run would be
    // measured as a regression of whatever the run compares.
    sky: SkySpec(
      dayLength: example.game.sky.dayLength,
      startTime: example.game.sky.startTime,
      cycle: example.game.sky.cycle,
    ),
  );

  final Stopwatch _clock = Stopwatch();
  _Phase _phase = _Phase.filling;
  double _phaseStart = 0.0;
  double? _fillMs;
  Vector3? _origin;
  Map<String, Object>? _world;
  double _measuredFrom = 0.0;
  int _bursts = 0;
  int _steps = 0;
  int _aimedSteps = 0;
  IVec3? _burstAt;

  void ready(VoxelGame game) {
    game.spawner.enabled = false;
    // The step reads the controls with no mouse captured: the view is turned
    // through them, as a player's is.
    game.playWithoutCapture = true;
    _clock.start();
  }

  double get _now => _clock.elapsedMicroseconds / 1e6;

  void _tick(VoxelGame game, double dt) {
    if (!game.ready) return;
    final origin = _origin ??= _start(game);
    _pose(game, origin, _phase == _Phase.measuring ? game.time - _measuredFrom : 0.0);
    switch (_phase) {
      case _Phase.filling:
        final window = (2 * radius + 1) * (2 * radius + 1);
        if (game.world.meshCount >= window && game.world.isIdle) {
          _fillMs = _now * 1000.0;
          _world = {'chunks': game.world.meshCount, 'faces': game.world.facesEmitted, 'meshes': game.world.chunksBuilt};
          if (scenario == Scenario.mobs) _spawnMobs(game, origin);
          if (peers > 0) unawaited(_host(game));
          _enter(_Phase.settling);
        } else if (_now > fillTimeout) {
          _report('[bench] the window did not fill in ${fillTimeout}s (${game.world.meshCount}/$window)');
          exit(1);
        }
      case _Phase.settling:
        if (game.remotePlayers.length < peers) {
          if (_now - _phaseStart < joinTimeout) return;
          _report('[bench] $peers peers did not join in ${joinTimeout}s (${game.remotePlayers.length})');
          exit(1);
        }
        if (_now - _phaseStart >= settle) {
          game.stats.startRecording();
          _measuredFrom = game.time;
          // A full turn over the recording, through the look.
          if (scenario != Scenario.fly) game.input.turn(-2 * math.pi / seconds, 0);
          _enter(_Phase.measuring);
        }
      case _Phase.measuring:
        _steps += 1;
        if (game.player.outline!.visible) _aimedSteps += 1;
        if (edits > 0 && game.time - _measuredFrom >= _bursts + 1.0) _burst(game, origin);
        if (_now - _phaseStart >= seconds) _finish(game);
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

  /// The player's pose [t] seconds of game time into the recording, held at
  /// t = 0 before; the look turns it while it records.
  void _pose(VoxelGame game, Vector3 origin, double t) {
    final player = game.player;
    player.velocity = Vector3.zero();
    switch (scenario) {
      case Scenario.orbit || Scenario.mobs:
        player.position.setFrom(origin);
        if (_phase != _Phase.measuring) player.yaw = 0.0;
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

  /// Hosts [game] on a free loopback port and starts [peers] scripted peers
  /// on an isolate of their own, so they take a core and not the UI thread.
  Future<void> _host(VoxelGame game) async {
    final session = await game.host(port: 0);
    await Isolate.spawn(_runPeers, (session.net.port, peers));
  }

  /// Edits [edits] cells in this step: the cells of a cube of leaves (not
  /// opaque, no light, so only its own chunk remeshes) inside the chunk
  /// two chunks east of [origin], over the highest ground under it the first
  /// time; set on odd bursts, cleared on even ones.
  void _burst(VoxelGame game, Vector3 origin) {
    _bursts += 1;
    final side = math.pow(edits, 1 / 3).ceil();
    assert(side <= 14, 'a burst of $edits cells does not fit inside one chunk');
    final at = _burstAt ??= () {
      final x0 = (origin.x.floor() >> 4 << 4) + 32 + 1, z0 = (origin.z.floor() >> 4 << 4) + 1;
      var y0 = 0;
      for (var z = z0; z < z0 + side; z++) {
        for (var x = x0; x < x0 + side; x++) {
          y0 = math.max(y0, game.world.groundHeight(x, z) + 1);
        }
      }
      return IVec3(x0, y0, z0);
    }();
    final (x0, y0, z0) = (at.x, at.y, at.z);
    final id = _bursts.isOdd ? game.blocks.indexOf('leaves') : BlockRegistry.air;
    var n = 0;
    for (var y = y0; n < edits; y++) {
      for (var z = z0; z < z0 + side && n < edits; z++) {
        for (var x = x0; x < x0 + side && n < edits; x++, n++) {
          if (!game.world.setBlock(IVec3(x, y, z), id)) throw StateError('burst $_bursts: ($x, $y, $z) did not change');
        }
      }
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
      'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'refreshHz': display.refreshRate,
      'window': '${size.width.round()}x${size.height.round()}',
      'dpr': view.devicePixelRatio,
      'graphics': {
        'scale': game.scene!.renderScale,
        'aa': graphics.antiAliasing.name,
        'shadows': graphics.shadows.enabled
            ? '${graphics.shadows.cascades}x${graphics.shadows.resolution} ${graphics.shadows.distance.round()}m'
            : 'off',
        'sunStep': graphics.shadows.sunStepDegrees,
      },
      'fillMs': _fillMs!.round(),
      ...?_world,
      'mobs': game.mobs.length,
      if (peers > 0) 'peers': game.remotePlayers.length,
      if (edits > 0) 'edits': edits,
      if (edits > 0) 'bursts': _bursts,
      if (aim) 'aimed': double.parse((_aimedSteps / _steps).toStringAsFixed(3)),
      ...report.toJson(1000.0 / display.refreshRate),
      'maxRssMb': (ProcessInfo.maxRss / (1 << 20)).round(),
    };
    _report('[bench] ${jsonEncode(line)}');
    exit(0);
  }
}

enum _Phase { filling, settling, measuring }

/// [Bench.peers] scripted peers of the host at the loopback's [port]: each
/// joins, drains what the host sends, and sends its pose [Bench.poseHz] times a
/// second, walking a circle of 4 m around the spawn.
Future<void> _runPeers((int, int) args) async {
  final (port, count) = args;
  for (var i = 0; i < count; i++) {
    final joined = await joinHost('127.0.0.1', port: port);
    final c = joined.connection..listen((_) {});
    final spawn = joined.spawn, phase = i * 2 * math.pi / count;
    var t = 0.0;
    Timer.periodic(const Duration(microseconds: 1000000 ~/ Bench.poseHz), (_) {
      t += 1 / Bench.poseHz;
      final a = phase + t * 0.5;
      c.send({
        't': 'pose',
        'p': [spawn.x + math.cos(a) * 4, spawn.y, spawn.z + math.sin(a) * 4],
        'yaw': a,
        'dead': false,
      });
    });
  }
}

/// Prints [line] where the runner reads it: a desktop runner reads the process's
/// stdout, which a release build's `print` does not reach; adb reads logcat, which
/// only `print` reaches.
void _report(String line) =>
    Platform.isMacOS || Platform.isLinux || Platform.isWindows ? stdout.writeln(line) : debugPrint(line);

// Runs the bench's script every step, after the game's own systems.
class _Driver extends GameSystem {
  _Driver(this.step);

  final void Function(VoxelGame game, double dt) step;

  @override
  void tick(VoxelGame game, double dt) => step(game, dt);
}
