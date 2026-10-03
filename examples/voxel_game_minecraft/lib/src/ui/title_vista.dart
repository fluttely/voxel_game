import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_scene/voxel_scene.dart' show DayNightSky, MirroredCamera;

import '../spec/game_spec.dart';

/// What the title sits on (`TitleSpec.background`): a world of its own, the
/// game's overworld under seed [seed] loaded [radius] chunks round its middle,
/// the camera circling it under a clear morning sky, a dark veil over it for
/// the menu's sake, and the meadow's track ([track]) under it all.
///
/// The world streams on worker isolates of its own: it is stopped when the
/// title goes, in the same frame the game's widget is built, before the game
/// opens its world, so two worlds never generate at once. So is the music:
/// its audio device closes before the game's opens.
class TitleVista extends StatefulWidget {
  /// The vista.
  const TitleVista({super.key});

  /// [TitleVista] as a `TitleSpec.background`.
  static Widget builder(BuildContext context) => const TitleVista();

  /// The world's seed: a meadow round a well, the sea and hills on the ring,
  /// and no tree up to the eye anywhere on it (the old vista's 42 grows the
  /// kit's tallest oaks across the camera's path).
  static const int seed = 37;

  /// Chunks loaded round the middle.
  static const int radius = 3;

  /// How far the camera stands off the middle, and how high above it.
  static const double orbitRadius = 30.0, orbitHeight = 16.0;

  /// Radians a second the camera turns by.
  static const double orbitSpeed = 0.06;

  /// The camera's vertical field of view, in degrees.
  static const double fov = 65.0;

  /// The time of day the sky stands at: the sun 48 degrees up.
  static const double hour = 0.378;

  /// A light haze in the horizon's colour, so the far side of the world
  /// pales.
  static const Haze haze = Haze(0x9EC7EB, 0.006);

  /// The music's track, one of the game's.
  static const String track = 'meadow';

  /// The middle the camera circles: two blocks over [world]'s surface at
  /// (8, 8).
  static Vector3 centreOf(GameWorld world) => Vector3(8.5, world.generator.surfaceHeight(8, 8) + 2.0, 8.5);

  /// Where the camera stands [angle] radians round [centre].
  static Vector3 eyeAt(Vector3 centre, double angle) =>
      centre + Vector3(math.cos(angle) * orbitRadius, orbitHeight, math.sin(angle) * orbitRadius);

  /// The camera [angle] radians round [centre], looking at it.
  static Camera cameraAt(Vector3 centre, double angle) => MirroredCamera(
    position: eyeAt(centre, angle),
    target: centre,
    up: Vector3(0.0, 1.0, 0.0),
    fovRadiansY: fov * math.pi / 180.0,
    fovNear: 0.1,
    fovFar: 500.0,
  );

  /// The music's gain under [settings]: the game's.
  static double musicGain(GameSettings settings) => settings.volume * settings.musicVolume;

  @override
  State<TitleVista> createState() => _TitleVistaState();
}

class _TitleVistaState extends State<TitleVista> {
  final GraphicsSpec _graphics = gameSpec.graphics!;
  late final GpuPacedScene _scene = GpuPacedScene(paced: _graphics.paced)..antiAliasingMode = _graphics.antiAliasing;
  final GameWorld _world = GameWorld(
    gameSpec.buildBlocks(),
    [gameSpec.world],
    TitleVista.seed,
    loadRadius: TitleVista.radius,
  );
  late final Vector3 _centre = TitleVista.centreOf(_world);
  double _angle = 0.0;
  bool _streaming = false;
  bool _disposed = false;
  SoundBank? _bank;
  MusicDirector? _music;

  @override
  void initState() {
    super.initState();
    final shadows = _graphics.shadows;
    final sky = DayNightSky(
      _scene,
      shadows: shadows.enabled,
      shadowCascades: shadows.cascades,
      shadowResolution: shadows.resolution,
      shadowDistance: shadows.distance,
      sunStepDegrees: shadows.sunStepDegrees,
    );
    _world.setSkyIntensity(sky.update(TitleVista.hour, haze: TitleVista.haze));
    _scene.add(_world.root!);
    unawaited(_stream());
    unawaited(_play());
  }

  Future<void> _stream() async {
    await _world.start();
    // Gone while its isolates started: dispose found no pool to stop.
    if (_disposed) return _world.dispose();
    _streaming = true;
  }

  Future<void> _play() async {
    final sounds = gameSpec.sounds;
    if (!sounds.enabled) return;
    final music = sounds.music!.tracks[TitleVista.track]!;
    final settings = (await VoxelGameWidget.defaultSettings()).read(GameSettings.of(gameSpec));
    // The audio device alone: the title plays no sound but the music.
    final bank = SoundBank(recipes: const {});
    if (!await bank.init()) return;
    if (_disposed) return bank.dispose();
    _bank = bank;
    final director = _music = MusicDirector(
      {TitleVista.track: ?music.asset},
      recipes: {if (music.score case final score?) TitleVista.track: score.toRecipe()},
      gain: TitleVista.musicGain(settings),
    );
    unawaited(director.setMood(TitleVista.track));
  }

  void _tick(double dt) {
    _angle += TitleVista.orbitSpeed * dt;
    if (_streaming) _world.update(_centre);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_music?.setMood(null));
    _bank?.dispose();
    _world.dispose();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scene.renderScale = _graphics.sceneScale(MediaQuery.devicePixelRatioOf(context));
    return Stack(
      fit: StackFit.expand,
      children: [
        SceneView(
          _scene,
          cameraBuilder: (elapsed) => TitleVista.cameraAt(_centre, _angle),
          onTick: (elapsed, dt) => _tick(dt),
        ),
        const IgnorePointer(child: ColoredBox(color: Color.fromRGBO(8, 10, 20, 0.35))),
      ],
    );
  }
}
