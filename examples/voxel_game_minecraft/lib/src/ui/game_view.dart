import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' hide Material;

import '../game/game.dart';
import 'hud.dart';
import 'inventory_screen.dart';
import 'journal_screen.dart';
import 'menus.dart';
import 'trade_screen.dart';
import 'touch_controls.dart';
import 'tutorial_card.dart';
import 'zone_card.dart';

/// The play session: the 3D view, the HUD painted over it, and whichever
/// screen is open (inventory, pause, death). Keyboard focus lives here.
///
/// Stage 24: a session can ask to be thrown away and rebuilt with the same
/// arguments (`Game.reloader`, Godot's `reload_current_scene`): the session
/// widget is keyed by a generation, so a new key disposes the old `Game` and
/// builds a fresh one.
class GameView extends StatefulWidget {
  const GameView({super.key, required this.args, required this.saveDir, this.onExitToTitle});
  final Map<String, String> args;
  final String saveDir;

  /// Stage 30: the pause menu's "Save & back to title".
  final VoidCallback? onExitToTitle;

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  int _generation = 0;

  @override
  Widget build(BuildContext context) => _GameSession(
        key: ValueKey<int>(_generation),
        args: widget.args,
        saveDir: widget.saveDir,
        onExitToTitle: widget.onExitToTitle,
        onReload: () {
          if (mounted) setState(() => _generation++);
        },
      );
}

class _GameSession extends StatefulWidget {
  const _GameSession({super.key, required this.args, required this.saveDir, required this.onReload, this.onExitToTitle});
  final Map<String, String> args;
  final String saveDir;
  final VoidCallback onReload;
  final VoidCallback? onExitToTitle;

  @override
  State<_GameSession> createState() => _GameSessionState();
}

class _GameSessionState extends State<_GameSession> {
  late final Game game;
  final FocusNode _focus = FocusNode(debugLabel: 'game');
  final GlobalKey _boundary = GlobalKey();
  final WorldMap _worldMap = WorldMap();
  String? _error;

  @override
  void initState() {
    super.initState();
    game = Game(args: widget.args, saveDir: widget.saveDir);
    game.screenshotter = _screenshot;
    game.mapStats = () => _worldMap.stats;
    game.reloader = widget.onReload;
    game.exitToTitle = widget.onExitToTitle;
    game.addListener(_onGameChanged);
    game.init().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e, StackTrace st) {
      debugPrint('[game] init failed: $e\n$st');
      if (mounted) setState(() => _error = '$e');
    });
  }

  void _onGameChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _screenshot(String path) async {
    // Called from the simulation tick, so wait for this frame to be painted
    // before reading the boundary back.
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  @override
  void dispose() {
    game.removeListener(_onGameChanged);
    game.shutdown();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Failed to start: $_error', style: const TextStyle(color: Colors.red))));
    }
    if (!game.ready) {
      return const Scaffold(
        backgroundColor: Color.fromRGBO(20, 26, 41, 1),
        body: Center(child: Text('Building the world...', style: TextStyle(color: Colors.white70, fontSize: 18))),
      );
    }
    final input = game.input;
    Widget? overlay;
    switch (game.screen) {
      case ScreenKind.inventory:
        overlay = InventoryScreen(game: game);
      case ScreenKind.pause:
        overlay = PauseMenu(game: game);
      case ScreenKind.death:
        overlay = DeathScreen(game: game);
      case ScreenKind.journal:
        overlay = JournalScreen(game: game);
      case ScreenKind.trade:
        overlay = TradeScreen(game: game);
      case ScreenKind.none:
        overlay = null;
    }
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: input.onKey,
      child: RepaintBoundary(
        key: _boundary,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The world's own pointers. It is the bottom of the stack on
            // purpose: a Stack hit-tests front to back and stops at the first
            // child that takes the touch, so a finger on an on-screen control
            // never reaches the simulation. Were the controls children of this
            // Listener instead, every button press would also arrive here and
            // be read as a tap on whatever the crosshair was pointing at.
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                _focus.requestFocus();
                if (game.screen == ScreenKind.none) {
                  if (!input.isCaptured && !game.player.isDead) input.capture();
                  input.onPointerDown(e);
                }
              },
              onPointerUp: input.onPointerUp,
              onPointerCancel: input.onPointerCancel,
              onPointerMove: input.onPointerMove,
              onPointerSignal: (e) {
                if (game.screen == ScreenKind.none) input.onPointerSignal(e);
              },
              child: MouseRegion(
                cursor: game.screen == ScreenKind.none && input.isCaptured ? SystemMouseCursors.none : SystemMouseCursors.basic,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SceneView(
                      game.scene,
                      cameraBuilder: (elapsed) => game.player.camera(),
                      onTick: (elapsed, dt) {
                        game.onFrame(dt);
                        _worldMap.update(dt, game);
                      },
                    ),
                    CustomPaint(painter: HudPainter(game, _worldMap, repaint: game.frame)),
                  ],
                ),
              ),
            ),
            // A phone's controls, off the screen while a screen of its own is
            // open or the body is dead — both are surfaces with their own
            // buttons, and a stick behind them would still be walking.
            if (game.touchControls && game.screen == ScreenKind.none && !game.player.isDead)
              TouchControls(input: input),
            const TutorialCard(), // stage 30
            if (game.playground != null) ZoneCard(playground: game.playground!), // stage 33
            ?overlay,
          ],
        ),
      ),
    );
  }
}
