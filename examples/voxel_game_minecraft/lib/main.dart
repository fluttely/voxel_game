import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:path_provider/path_provider.dart';

import 'src/game/game_state.dart';
import 'src/game/net.dart';
import 'src/game/settings.dart';
import 'src/game/sfx.dart';
import 'src/game/worlds.dart';
import 'src/ui/game_view.dart';
import 'src/ui/paced_scene.dart';
import 'src/ui/title_screen.dart';

/// `--k=v` becomes `args['--k='] = v`; a bare `--flag` becomes `args['--flag'] = ''`.
Map<String, String> parseArgs(List<String> raw) {
  final out = <String, String>{};
  for (final a in raw) {
    final eq = a.indexOf('=');
    if (eq > 0) {
      out[a.substring(0, eq + 1)] = a.substring(eq + 1);
    } else {
      out[a] = '';
    }
  }
  return out;
}

/// A phone or tablet plays this game in landscape and nothing else: the HUD,
/// the hotbar and the 3D view are all laid out for a wide viewport, and a
/// Backbone-style controller physically holds the device that way. Desktop
/// windows are sized by their window manager, so this is a mobile-only call.
Future<void> _lockLandscape() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Status and navigation bars slide away but come back on a swipe, so the
  // player can still leave; `immersive` alone would fight every stray touch.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

Future<void> main(List<String> rawArgs) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _lockLandscape();
  final args = parseArgs(rawArgs);
  final support = await getApplicationSupportDirectory();
  final saveRoot = '${support.path}/voxel_game_minecraft';
  // Stage 24: the settings file sits beside worlds/ (Godot's user://settings.cfg).
  Settings.instance.path = '$saveRoot/settings.cfg';
  Settings.instance.loadFile();
  Settings.instance.applyGlobals();
  // Stage 30: the probe marks the tutorial done in a file of its own, never in
  // this machine's settings.cfg (Godot's probe writes the real one).
  if (args.containsKey('--stage30')) Settings.instance.path = '$saveRoot/settings_probe30.cfg';
  Worlds.root = '$saveRoot/worlds'; // stage 30: the world list's slots
  await Scene.initializeStaticResources();
  PacedScene.log = args.containsKey('--pace-probe');
  // Audio comes up in the background; the game plays silently until it does.
  Sfx.init();
  runApp(MinecraftApp(args: args, saveRoot: saveRoot));
}

class MinecraftApp extends StatelessWidget {
  const MinecraftApp({super.key, required this.args, required this.saveRoot});
  final Map<String, String> args;
  final String saveRoot;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voxel Minecraft',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: _Launcher(args: args, saveRoot: saveRoot),
    );
  }
}

/// Mirrors Godot's `title_screen.gd` argument handling: --host, --join=ip,
/// --screenshot=, --new, --continue, --seed= and --slot= skip straight into
/// the game unless --title-probe asks for the title; otherwise the title.
class _Launcher extends StatefulWidget {
  const _Launcher({required this.args, required this.saveRoot});
  final Map<String, String> args;
  final String saveRoot;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  Widget? _child;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final args = widget.args;
    final gs = GameState.instance;
    if (args.containsKey('--class=')) gs.playerClass = args['--class=']!;
    if (!args.containsKey('--title-probe')) {
      if (args.containsKey('--host')) {
        gs.freshWorld = true;
        gs.worldName = 'host_probe';
        if (args.containsKey('--seed=')) gs.seedValue = int.parse(args['--seed=']!);
        if (await Net.instance.host()) _enter();
        return;
      }
      if (args.containsKey('--join=')) {
        if (args.containsKey('--seed=')) gs.seedValue = int.parse(args['--seed=']!);
        if (!await Net.instance.join(args['--join=']!)) return;
        // Wait for the host's hello before building anything: it carries the seed,
        // and a world built on the wrong seed would put the spawn search on
        // terrain that is about to be replaced.
        final until = DateTime.now().add(const Duration(seconds: 8));
        while (!Net.instance.connected && DateTime.now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        _enter();
        return;
      }
      if (args.containsKey('--screenshot=') ||
          args.containsKey('--new') ||
          args.containsKey('--continue') ||
          args.containsKey('--seed=') ||
          args.containsKey('--slot=')) {
        if (args.containsKey('--new')) gs.freshWorld = true;
        if (args.containsKey('--seed=')) gs.seedValue = int.parse(args['--seed=']!);
        if (args.containsKey('--world=')) gs.worldName = args['--world=']!;
        _enter();
        return;
      }
    }
    _showTitle(true);
  }

  void _showTitle(bool first) {
    setState(() => _child = TitleScreen(key: UniqueKey(), args: widget.args, onStart: _enter, runProbes: first));
  }

  void _enter() {
    setState(() => _child = GameView(
          key: UniqueKey(),
          args: widget.args,
          saveDir: '${widget.saveRoot}/worlds/${GameState.instance.worldName}',
          onExitToTitle: () => _showTitle(false),
        ));
  }

  @override
  Widget build(BuildContext context) => _child ?? const Scaffold(backgroundColor: Color.fromRGBO(20, 26, 41, 1));
}
