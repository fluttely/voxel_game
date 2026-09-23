import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sound_recipes/sound_recipes.dart';
import 'package:voxel_engine/core.dart' show IVec3;
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../spec/voxel_game_spec.dart';
import 'default_hud.dart';
import 'inventory_screen.dart';
import '../world/world_save.dart';

/// Builds an overlay over the running game; rebuilt every frame, so keep it
/// light. It never receives pointer events (they are the game's).
typedef HudBuilder = Widget Function(BuildContext context, VoxelGame game);

/// Loads the renderer and runs [spec] full screen: the one call a game's
/// `main` needs.
///
/// ```dart
/// void main() => runVoxelGame(myGame);
/// ```
///
/// With [saveSlot] the world is kept in that slot of the app's support
/// folder (`worlds/<slot>`): loaded when it exists, saved every minute and
/// when the widget goes away. With [hostPort] others can join the game on
/// that port; with [join] (`'192.168.0.10'`, or `'host:port'`) this game
/// joins one instead.
Future<void> runVoxelGame(VoxelGameSpec spec,
    {String title = 'Voxel game', HudBuilder? hud, String? saveSlot, int? hostPort, String? join}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await VoxelGameWidget.loadResources();
  runApp(MaterialApp(
    title: title,
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: Scaffold(body: VoxelGameWidget(spec: spec, hud: hud, saveSlot: saveSlot, hostPort: hostPort, join: join)),
  ));
}

/// A running [VoxelGameSpec]: the 3D view, the controls (keyboard, mouse with
/// pointer lock, gamepad) and a HUD. Click to play, Escape to free the mouse.
///
/// Call [loadResources] once before the first one is built (`runVoxelGame`
/// does).
class VoxelGameWidget extends StatefulWidget {
  /// A game of [spec] with [hud] over it ([DefaultHud] when null);
  /// [onReady] receives the game once it runs.
  const VoxelGameWidget({
    super.key,
    required this.spec,
    this.hud,
    this.onReady,
    this.saveSlot,
    this.saves,
    this.autosave = const Duration(minutes: 1),
    this.hostPort,
    this.join,
  });

  /// Host the game on this port, or null for a game nobody joins.
  final int? hostPort;

  /// Join the game at this address (`host` or `host:port`, port 7777 by
  /// default) instead of starting one; its world is the host's and is never
  /// saved here.
  final String? join;

  /// The game.
  final VoxelGameSpec spec;

  /// The overlay; the default HUD when null.
  final HudBuilder? hud;

  /// Called once the game has started.
  final void Function(VoxelGame game)? onReady;

  /// The save slot the world lives in, or null for a world never saved.
  final String? saveSlot;

  /// Where the slots are; the app support folder's `worlds` when null.
  final WorldSaves? saves;

  /// How often the world is saved while it runs.
  final Duration autosave;

  /// The app's default saves: `<application support>/worlds`.
  static Future<WorldSaves> defaultSaves() async => WorldSaves(Directory('${(await getApplicationSupportDirectory()).path}/worlds'));

  /// Loads flutter_scene's static resources and the terrain shader.
  static Future<void> loadResources() async {
    await Scene.initializeStaticResources();
    await TerrainMaterial.loadLibrary();
  }

  @override
  State<VoxelGameWidget> createState() => _VoxelGameWidgetState();
}

class _VoxelGameWidgetState extends State<VoxelGameWidget> {
  VoxelGame? _game;
  final FocusNode _focus = FocusNode();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  bool _disposed = false;

  WorldSaves? _saves;
  Timer? _autosave;
  SoundBank? _bank;
  MusicDirector? _music;
  Timer? _moodTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final join = widget.join;
    final VoxelGame game;
    if (join != null) {
      final parts = join.split(':');
      game = await VoxelGame.joinGame(widget.spec, parts[0], port: parts.length > 1 ? int.parse(parts[1]) : 7777);
    } else {
      final slot = widget.saveSlot;
      SavedWorld? saved;
      if (slot != null) {
        final saves = _saves = widget.saves ?? await VoxelGameWidget.defaultSaves();
        if (saves.exists(slot)) saved = saves.read(slot);
      }
      game = await VoxelGame.start(widget.spec, save: saved);
      final port = widget.hostPort;
      if (port != null) await game.host(port: port);
    }
    if (_disposed) {
      game.dispose();
      return;
    }
    game.input.attachDevices();
    game.openScreen.addListener(_screenChanged);
    setState(() => _game = game);
    unawaited(_startAudio(game));
    if (widget.saveSlot != null && join == null) _autosave = Timer.periodic(widget.autosave, (_) => _save());
    widget.onReady?.call(game);
  }

  Future<void> _startAudio(VoxelGame game) async {
    final sound = widget.spec.sounds;
    if (!sound.enabled) return;
    final bank = SoundBank(recipes: {...StockSounds.all, ...sound.recipes}, assets: sound.assets);
    if (!await bank.init() || _disposed) return;
    _bank = bank;
    game.sounds = bank;
    if (sound.music.isEmpty) return;
    final music = _music = MusicDirector(sound.music, gain: sound.musicVolume);
    _moodTimer = Timer.periodic(const Duration(seconds: 1), (_) => music.setMood(_moodOf(game, sound.music)));
  }

  /// The music's mood: the cave underground, the biome's own track, else day
  /// or night.
  static String? _moodOf(VoxelGame game, Map<String, String> tracks) {
    final p = game.player.position;
    final cell = IVec3.floor(p);
    final underground = p.y < game.world.groundHeight(cell.x, cell.z) - 6 && game.world.lightAt(cell).sky < 4;
    if (underground && tracks.containsKey('cave')) return 'cave';
    final biome = game.world.generator.biomeAt(cell.x, cell.z).name;
    if (tracks.containsKey(biome)) return biome;
    final key = game.daylight > 0.3 ? 'day' : 'night';
    return tracks.containsKey(key) ? key : null;
  }

  void _save() {
    final game = _game, saves = _saves, slot = widget.saveSlot;
    if (game == null || saves == null || slot == null || !game.ready || !game.authority) return;
    saves.save(game, slot);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _moodTimer?.cancel();
    _music?.setMood(null);
    _bank?.dispose();
    _save();
    _disposed = true;
    _game?.openScreen.removeListener(_screenChanged);
    _game?.dispose();
    _focus.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _screenChanged() {
    final game = _game;
    if (game == null) return;
    // The screen is the arbiter of the pointer: opening frees it, closing
    // takes it back, whoever asked for the change.
    if (game.openScreen.value != null) {
      game.input.release();
    } else {
      game.input.capture();
    }
    setState(() {});
  }

  void _closeScreen(VoxelGame game) => game.openScreen.value = null;

  void _tick(VoxelGame game, double dt) {
    final input = game.input;
    if (input.captureLost) {
      input.captureLost = false;
      input.releaseKeys();
    }
    game.gameplay = (input.wantCapture || game.playWithoutCapture) && game.openScreen.value == null;
    game.frame(dt);
    _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    if (game == null) {
      return const ColoredBox(color: Color(0xFF0E1420), child: Center(child: Text('Generating the world...')));
    }
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: game.input.onKey,
      child: Listener(
        onPointerDown: (e) {
          _focus.requestFocus();
          if (game.openScreen.value != null) return;
          if (!game.input.wantCapture) {
            game.input.capture();
            return;
          }
          game.input.onPointerDown(e);
        },
        onPointerUp: game.input.onPointerUp,
        onPointerCancel: game.input.onPointerCancel,
        onPointerMove: game.input.onPointerMove,
        onPointerSignal: game.input.onPointerSignal,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SceneView(game.scene!, cameraBuilder: (elapsed) => game.camera(), onTick: (elapsed, dt) => _tick(game, dt)),
            IgnorePointer(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, _) => (widget.hud ?? DefaultHud.builder)(context, game),
              ),
            ),
            if (game.openScreen.value != null)
              InventoryScreen(game: game, station: game.openScreen.value!, onClose: () => _closeScreen(game)),
          ],
        ),
      ),
    );
  }
}
