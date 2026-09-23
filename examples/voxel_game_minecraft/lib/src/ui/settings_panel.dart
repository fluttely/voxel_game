import 'package:flutter/material.dart';

import '../game/game.dart';
import '../game/game_state.dart';
import '../game/settings.dart';
import '../game/worlds.dart';

/// Stage 30: the settings rows (stage 24) built into any column. The pause menu
/// passes the live [game] so render distance and weather apply at once; the
/// title screen passes null and the values wait in `Settings` for the next
/// world (Godot's `SettingsPanel.build(box, main)`).
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, this.game});
  final Game? game;

  /// The stats block (stage 30): what `GameState` counted in this world.
  static String statsText() {
    final gs = GameState.instance;
    return 'Play time ${Worlds.playTimeLabel(gs.playTime)} · walked ${gs.distanceWalked.toInt()} m\n'
        'Blocks broken ${gs.blocksMined} · placed ${gs.blocksPlaced}\n'
        'Mobs killed ${gs.mobsKilled} · deaths ${gs.deaths} · dimension trips ${gs.dimensionVisits}';
  }

  static Widget button(String text, VoidCallback? cb, {double height = 38}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: SizedBox(height: height, width: double.infinity, child: FilledButton(onPressed: cb, child: Text(text))),
      );

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  Settings get settings => Settings.instance;

  /// Godot's `HSlider.step`: 0.05 up to 1, 0.1 below 10, 1 otherwise.
  Widget _slider(String text, double lo, double hi, double value, void Function(double) cb) {
    final step = hi <= 1.0 ? 0.05 : (hi < 10.0 ? 0.1 : 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$text: ${value.toStringAsFixed(1)}', style: const TextStyle(fontSize: 13, color: Colors.white)),
        SizedBox(
          height: 30,
          child: Slider(
            min: lo,
            max: hi,
            divisions: ((hi - lo) / step).round(),
            value: value.clamp(lo, hi),
            onChanged: (v) => setState(() => cb(v)),
          ),
        ),
      ],
    );
  }

  /// A switch row. It has no fixed height on purpose: these labels say what the
  /// setting does, and at the width of the pause panel the longer ones wrap to
  /// two lines. Pinned to one line's worth of height they overflowed their box
  /// and drew over the row beneath.
  Widget _check(String text, bool value, void Function(bool) cb) => SwitchListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.zero,
        title: Text(text, style: const TextStyle(fontSize: 14, color: Colors.white)),
        value: value,
        onChanged: (v) => setState(() => cb(v)),
      );

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _slider('Render distance (chunks)', 4.0, 10.0, game != null ? game.world.loadRadius.toDouble() : settings.renderRadius.toDouble(), (v) {
          settings.renderRadius = v.round();
          if (game != null && v.round() != game.world.loadRadius) game.applyRenderDistance(v.round());
        }),
        _slider('Mouse sensitivity', 0.3, 3.0, settings.sensitivity, (v) {
          settings.sensitivity = v;
          settings.applyGlobals();
        }),
        _slider('Field of view', 60.0, 100.0, settings.fov, (v) {
          settings.fov = v;
          settings.applyGlobals();
        }),
        _slider('Master volume', 0.0, 1.0, settings.volume, (v) {
          settings.volume = v;
          settings.applyGlobals();
        }),
        _slider('Music volume', 0.0, 1.0, settings.musicVolume, (v) {
          settings.musicVolume = v;
          settings.applyGlobals();
        }),
        _check('Weather (off = always clear)', settings.weather, (on) {
          settings.weather = on;
          game?.weather.setEnabled(on);
        }),
        _check('Show FPS', settings.showFps, (on) => settings.showFps = on),
        _check('View bobbing (the camera dips with each step)', settings.viewBob, (on) => settings.viewBob = on),
        _check('Climb walls (hold Space against a wall)', settings.climbWalls, (on) => settings.climbWalls = on),
        _check('Tutorial done (off = show it on the next new world)', settings.tutorialDone, (on) => settings.tutorialDone = on),
      ],
    );
  }
}
