import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import '../game/game.dart';
import '../game/game_state.dart';
import '../game/music.dart';
import '../game/net.dart';
import '../game/settings.dart';
import '../game/sfx.dart';
import '../game/worlds.dart';
import '../player/player.dart';
import 'package:voxel_scene/voxel_scene.dart';
import '../world/voxel_world.dart';
import 'credits_screen.dart';
import 'paced_scene.dart';
import 'settings_panel.dart';
import 'world_list.dart';

enum _Panel { none, worlds, playground, multiplayer, settings, credits }

/// Stage 30: the title screen — Play (the world list), Multiplayer (host a
/// world / join an address), Settings (the shared `SettingsPanel`), Credits,
/// Quit — over a slowly orbiting voxel vista: a second, real `VoxelWorld`
/// (radius [vistaRadius], seed [vistaSeed]) in its own `Scene` with its own
/// sky and sun, drawn by its own `SceneView`. Leaving for a world disposes the
/// vista's isolate pool before the game builds its own, so two worlds never
/// generate at once. The launcher skips this screen on a probe boot unless
/// `--title-probe` asks for it.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key, required this.args, required this.onStart, this.runProbes = true});
  final Map<String, String> args;

  /// `GameState` is filled (`Worlds.start` or the join); build the session.
  final VoidCallback onStart;

  /// False when the title comes back from a world: the probe flags already ran.
  final bool runProbes;

  static const int vistaSeed = 42;
  static const int vistaRadius = 3;
  static const double orbitRadius = 30.0;
  static const double orbitHeight = 16.0;
  static const double orbitSpeed = 0.06; // rad/s
  static const String probe30StatsSlot = 'probe30_stats';
  static const List<String> buttonLabels = ['Play', 'Playground', 'Multiplayer', 'Settings', 'Credits', 'Quit'];

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  final Scene _scene = PacedScene();
  VoxelWorld? _world;
  bool _disposed = false;
  bool _music = false;
  vm.Vector3 _centre = vm.Vector3(8.5, 70.0, 8.5);
  double _angle = 0.0;
  _Panel _panel = _Panel.none;
  bool _worldsForm = false;
  double _creditsStart = 0.0;
  String _status = '';
  final GlobalKey _boundary = GlobalKey();
  final FocusNode _focus = FocusNode(debugLabel: 'title');
  final TextEditingController _ip = TextEditingController(text: '127.0.0.1');
  int _hostPick = 0;
  String _joinClass = 'warrior';
  String _playgroundClass = 'warrior';
  bool _busy = false;

  Map<String, String> get args => widget.args;

  @override
  void initState() {
    super.initState();
    _buildVista();
    if (widget.runProbes) {
      if (args.containsKey('--stage30')) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _probeStage30());
      } else if (args.containsKey('--title-probe')) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _probeCapture());
      }
    }
  }

  // --- the vista -------------------------------------------------------------------------

  Future<void> _buildVista() async {
    final sky = GradientSkySource(sunSharpness: 600.0);
    _scene.skybox = Skybox(sky);
    final sun = SunLight(
      sky,
      castsShadow: true,
      shadowMaxDistance: 110.0,
      shadowMapResolution: 2048,
      shadowCascadeCount: 4,
      shadowSoftness: 0.04,
      shadowDepthBias: 0.02,
      shadowNormalBias: 0.06,
      shadowAmbientStrength: 0.0,
    );
    _scene.sunLight = sun;
    _scene.toneMapping = ToneMappingMode.aces;
    // Godot's DirectionalLight3D at (-48, 35): the sun 48 degrees up.
    final elev = 48.0 * math.pi / 180.0, az = 35.0 * math.pi / 180.0;
    final sunColor = vm.Vector3(1.0, 0.95, 0.85);
    final horizon = vm.Vector3(0.62, 0.78, 0.92);
    sky
      ..zenithColor = vm.Vector3(0.20, 0.42, 0.85)
      ..horizonColor = horizon
      ..groundColor = horizon * 0.9
      ..sunDirection = vm.Vector3(math.sin(az) * math.cos(elev), math.sin(elev), math.cos(az) * math.cos(elev)).normalized()
      ..sunColor = sunColor * 2.9;
    sun
      ..color = sunColor
      ..intensity = 3.0 * 0.85 * Game.sunScale;
    _scene.environment = EnvironmentMap.constantDiffuse(vm.Vector3(0.80, 0.84, 0.92) * (0.4 * 1.25 * Game.ambientScale));
    _scene.fog
      ..enabled = true
      ..mode = FogMode.exponential
      ..density = 0.006
      ..color = horizon
      ..skyColorInfluence = 1.0
      ..maxOpacity = 0.9;
    await TerrainMaterial.loadLibrary(); // stage 31: the vista's chunks draw with the terrain shader too
    final world = VoxelWorld(seedValue: TitleScreen.vistaSeed, loadRadius: TitleScreen.vistaRadius);
    _scene.add(world.root);
    await world.start();
    if (_disposed) {
      world.dispose();
      return;
    }
    _centre = vm.Vector3(8.5, world.surfaceHeight(8, 8) + 2.0, 8.5);
    world.updateAround(_centre);
    _world = world;
  }

  void _disposeVista() {
    if (_disposed) return;
    _disposed = true;
    _world?.dispose();
    _world = null;
  }

  void _tick(double dt) {
    final world = _world;
    if (_disposed || world == null) return;
    _angle += TitleScreen.orbitSpeed * dt;
    world.update();
    world.updateAround(_centre);
    if (!_music && Sfx.ready) {
      _music = true;
      Music.instance.setContext(0, false, false); // the Meadow mood under the title
    }
  }

  Camera _camera() {
    final pos = _centre + vm.Vector3(math.cos(_angle) * TitleScreen.orbitRadius, TitleScreen.orbitHeight, math.sin(_angle) * TitleScreen.orbitRadius);
    return MirroredCamera(position: pos, target: _centre, up: vm.Vector3(0, 1, 0), fovRadiansY: 65.0 * math.pi / 180.0, fovNear: 0.1, fovFar: 500.0);
  }

  @override
  void dispose() {
    _disposeVista();
    _focus.dispose();
    _ip.dispose();
    super.dispose();
  }

  // --- the menu --------------------------------------------------------------------------

  void _leave() {
    _disposeVista();
    widget.onStart();
  }

  void _playSlot(String slot) {
    Worlds.start(slot);
    _leave();
  }

  void _close() => setState(() => _panel = _Panel.none);

  Widget _menu() {
    const shadow = [Shadow(color: Color.fromRGBO(0, 0, 0, 0.7), offset: Offset(3, 3))];
    final actions = <VoidCallback>[
      () => setState(() => _panel = _Panel.worlds),
      () => setState(() => _panel = _Panel.playground),
      () => setState(() {
            _hostPick = 0;
            _panel = _Panel.multiplayer;
          }),
      () => setState(() => _panel = _Panel.settings),
      () => setState(() {
            _creditsStart = 0.0;
            _panel = _Panel.credits;
          }),
      () => exit(0),
    ];
    return Center(
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Voxel Minecraft', style: TextStyle(fontSize: 58, color: Colors.white, shadows: shadow)),
            const Text('a Minecraft clone built on voxel_game',
                style: TextStyle(fontSize: 15, color: Colors.white, shadows: [Shadow(color: Color.fromRGBO(0, 0, 0, 0.7), offset: Offset(1, 1))])),
            const SizedBox(height: 20),
            for (var i = 0; i < TitleScreen.buttonLabels.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: FilledButton(onPressed: actions[i], child: Text(TitleScreen.buttonLabels[i], style: const TextStyle(fontSize: 20))),
                ),
              ),
            const SizedBox(height: 6),
            Text(_status, style: const TextStyle(fontSize: 13, color: Color.fromRGBO(217, 217, 230, 1))),
          ],
        ),
      ),
    );
  }

  /// Settings and Multiplayer share one framed box in the middle of the screen.
  Widget _framed(String title, List<Widget> children) => Container(
        color: const Color.fromRGBO(8, 10, 20, 0.86),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, color: Colors.white)),
                const SizedBox(height: 6),
                ...children,
              ],
            ),
          ),
        ),
      );

  Widget _settings() => _framed('Settings', [
        const SettingsPanel(),
        SettingsPanel.button('Back', () {
          Settings.instance.save();
          _close();
        }, height: 44),
      ]);

  /// Stage 33: the playground — a new creative world with every feature laid
  /// out around the spawn.
  Widget _playground() {
    const white = TextStyle(fontSize: 14, color: Colors.white);
    return _framed('Playground', [
      const Text(
          'A new creative world built to show everything the game can do. You start in a hub, surrounded by nine exhibits: '
          'every block, shapes and building, redstone, rails and minecarts, water, lava and the portal, a farm with animals '
          'and villagers, a monster arena with bosses to summon, and light and mining.',
          style: white),
      const SizedBox(height: 6),
      const Text('F5 fly · F7 weather · F8 time of day · F9 rebuild the exhibit you stand in · the hub waypoint opens a world tour',
          style: TextStyle(fontSize: 13, color: Color.fromRGBO(191, 217, 255, 1))),
      const SizedBox(height: 8),
      Row(children: [
        for (final e in Player.classes.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: SizedBox(
                height: 36,
                child: _playgroundClass == e.key
                    ? FilledButton(onPressed: () => setState(() => _playgroundClass = e.key), child: Text(e.value.name))
                    : OutlinedButton(onPressed: () => setState(() => _playgroundClass = e.key), child: Text(e.value.name)),
              ),
            ),
          ),
      ]),
      SettingsPanel.button('Build a new playground', () => _playSlot(Worlds.createPlayground(_playgroundClass)), height: 44),
      SettingsPanel.button('Back', _close, height: 44),
    ]);
  }

  Widget _multiplayer() {
    final entries = Worlds.list();
    final int pick = _hostPick.clamp(0, math.max(entries.length - 1, 0)).toInt();
    const white = TextStyle(color: Colors.white);
    return _framed('Multiplayer', [
      Text('Host one of your worlds on port ${Net.port}, or join a host by address.', style: const TextStyle(fontSize: 13, color: Colors.white)),
      const SizedBox(height: 6),
      DropdownButton<int>(
        value: entries.isEmpty ? null : pick,
        isExpanded: true,
        hint: const Text('no worlds yet — create one under Play', style: white),
        dropdownColor: const Color.fromRGBO(20, 26, 41, 1),
        items: [
          for (var i = 0; i < entries.length; i++)
            DropdownMenuItem(value: i, child: Text('${entries[i].name} (${Worlds.modeLabel(entries[i])}, seed ${entries[i].seed})', style: white)),
        ],
        onChanged: entries.isEmpty ? null : (v) => setState(() => _hostPick = v ?? 0),
      ),
      SettingsPanel.button(
        'Host the selected world',
        entries.isEmpty || _busy
            ? null
            : () async {
                Worlds.start(entries[pick].slot);
                setState(() => _busy = true);
                if (await Net.instance.host()) {
                  _leave();
                } else if (mounted) {
                  setState(() {
                    _busy = false;
                    _status = 'Could not open port ${Net.port}';
                    _panel = _Panel.none;
                  });
                }
              },
        height: 44,
      ),
      const SizedBox(height: 10),
      const Text('Join address', style: TextStyle(fontSize: 14, color: Colors.white)),
      TextField(controller: _ip, style: white),
      const SizedBox(height: 6),
      Row(children: [
        for (final e in Player.classes.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: SizedBox(
                height: 36,
                child: _joinClass == e.key
                    ? FilledButton(onPressed: () => setState(() => _joinClass = e.key), child: Text(e.value.name))
                    : OutlinedButton(onPressed: () => setState(() => _joinClass = e.key), child: Text(e.value.name)),
              ),
            ),
          ),
      ]),
      SettingsPanel.button(
        'Join',
        _busy
            ? null
            : () async {
                final gs = GameState.instance;
                gs.resetStats();
                gs.playerClass = _joinClass;
                gs.creative = false;
                setState(() => _busy = true);
                if (await Net.instance.join(_ip.text.trim())) {
                  // The host's hello carries the seed (as the --join= boot waits for it).
                  final until = DateTime.now().add(const Duration(seconds: 8));
                  while (!Net.instance.connected && DateTime.now().isBefore(until)) {
                    await Future<void>.delayed(const Duration(milliseconds: 50));
                  }
                  _leave();
                } else if (mounted) {
                  setState(() {
                    _busy = false;
                    _status = 'Bad address';
                    _panel = _Panel.none;
                  });
                }
              },
        height: 44,
      ),
      SettingsPanel.button('Back', _close, height: 44),
    ]);
  }

  Widget? _panelWidget() {
    switch (_panel) {
      case _Panel.none:
        return null;
      case _Panel.worlds:
        return WorldList(onStart: _playSlot, onClosed: _close, showForm: _worldsForm);
      case _Panel.playground:
        return _playground();
      case _Panel.multiplayer:
        return _multiplayer();
      case _Panel.settings:
        return _settings();
      case _Panel.credits:
        return CreditsScreen(onClosed: _close, startSeconds: _creditsStart);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = _panelWidget();
    return Scaffold(
      backgroundColor: const Color.fromRGBO(20, 26, 41, 1),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape && _panel != _Panel.none) {
            _close();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: RepaintBoundary(
          key: _boundary,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SceneView(_scene, cameraBuilder: (elapsed) => _camera(), onTick: (elapsed, dt) => _tick(dt)),
              const IgnorePointer(child: ColoredBox(color: Color.fromRGBO(8, 10, 20, 0.35))),
              panel ?? _menu(),
            ],
          ),
        ),
      ),
    );
  }

  // --- probes ----------------------------------------------------------------------------

  Future<void> _frames(int n) async {
    for (var i = 0; i < n; i++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// `--title-probe --screenshot=<png>`: the title (with `--open-worlds`: the
  /// world list and its form; Flutter-only `--open-credits`: the credits part
  /// way through the stage rows) captured after `--frames` and the vista's
  /// meshing.
  Future<void> _probeCapture() async {
    final frames = int.tryParse(args['--frames='] ?? '') ?? 120;
    if (args.containsKey('--open-worlds')) {
      setState(() {
        _worldsForm = true;
        _panel = _Panel.worlds;
      });
    } else if (args.containsKey('--open-playground')) {
      setState(() => _panel = _Panel.playground);
    } else if (args.containsKey('--open-credits')) {
      setState(() {
        _creditsStart = double.tryParse(args['--credits-t='] ?? '') ?? 20.0;
        _panel = _Panel.credits;
      });
    }
    await _frames(frames);
    for (var i = 0; i < 900 && (_world == null || !_world!.isIdle); i++) {
      await _frames(1);
    }
    await _frames(10);
    debugPrint('[probe] title: vista chunks=${_world?.loadedChunkCount ?? 0} faces=${_world?.facesEmitted ?? 0} buttons=${TitleScreen.buttonLabels.length} panel=${_panel.name}');
    final path = args['--screenshot='] ?? '';
    if (path != '') {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final f = File(path);
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
          debugPrint('[probe] screenshot saved to $path');
        }
      }
    }
    exit(0);
  }

  /// `--stage30 --title-probe`: the title's buttons, the world list round trip
  /// (create, rename, delete), the credits parse; then a creative mage world in
  /// [TitleScreen.probe30StatsSlot] is started through the same path as Play,
  /// and `Game` prints the rest.
  Future<void> _probeStage30() async {
    await _frames(3);
    debugPrint('[probe] stage30 title: buttons=${TitleScreen.buttonLabels.length} (${TitleScreen.buttonLabels.join(', ')})');
    for (final e in Worlds.list()) {
      if (e.slot.startsWith('probe30_')) Worlds.delete(e.slot); // a previous run's leftovers
    }
    final slot = Worlds.create('Probe World', '4242', 'creative', 'mage', slotPrefix: 'probe30_');
    final entries = Worlds.list();
    final found = entries.any((e) => e.slot == slot && e.name == 'Probe World' && e.mode == 'creative' && e.playerClass == 'mage');
    debugPrint("[probe] stage30 worlds: created 'Probe World' seed=${Worlds.entry(slot)!.seed} mode=creative class=mage -> list entries=${entries.length} contains=$found (slot $slot)");
    final renamed = Worlds.rename(slot, 'Probe Renamed') && Worlds.entry(slot)!.name == 'Probe Renamed';
    debugPrint("[probe] stage30 renamed -> 'Probe Renamed' ok=$renamed");
    Worlds.delete(slot);
    debugPrint('[probe] stage30 deleted -> entries=${Worlds.list().length} (slot gone=${!Directory('${Worlds.root}/$slot').existsSync()})');
    final stages = await CreditsScreen.loadStages();
    debugPrint('[probe] stage30 credits: stage rows parsed=${stages.length} (first "${stages.first}", last "${stages.last}")');
    // The world the in-game half plays: creative, mage, the tutorial armed.
    Settings.instance.tutorialDone = false;
    final play = Worlds.create('Stats', '42', 'creative', 'mage', slotPrefix: 'probe30_');
    if (play != TitleScreen.probe30StatsSlot) {
      debugPrint('[probe] stage30 probe slot name drifted: $play');
      exit(1);
    }
    _playSlot(play);
    debugPrint('[probe] stage30 title left: vista disposed=$_disposed, starting slot $play');
  }
}
