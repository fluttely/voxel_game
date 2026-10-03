import 'package:flutter/material.dart';

import '../settings/game_settings.dart';
import '../spec/voxel_game_spec.dart';

/// The rows of the player's [GameSettings], for any column: a slider for each
/// value in its range, a switch for each flag. It holds no game: it shows
/// [value] and hands every change to [onChanged], so it serves a running game
/// (`SettingsMenu`) and a screen with none alike.
///
/// What [spec] declares, it offers: the volume only with `SoundSpec.enabled`,
/// the music's only when the game has music, the weather only when its sky
/// has some.
class SettingsPanel extends StatelessWidget {
  /// The settings [value] of a game of [spec], each change to [onChanged].
  const SettingsPanel({super.key, required this.spec, required this.value, required this.onChanged});

  /// The game they are for.
  final VoxelGameSpec spec;

  /// What is set now.
  final GameSettings value;

  /// Takes a change, with every other value as it was.
  final ValueChanged<GameSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final sound = spec.sounds;
    String percent(double v) => '${(v * 100).round()} %';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _slider(
          'Render distance',
          '${value.renderDistance} chunks',
          value.renderDistance.toDouble(),
          GameSettings.minRenderDistance.toDouble(),
          GameSettings.maxRenderDistance.toDouble(),
          GameSettings.maxRenderDistance - GameSettings.minRenderDistance,
          (v) => value.copyWith(renderDistance: v.round()),
        ),
        _slider(
          'Look speed',
          '× ${value.lookSpeed.toStringAsFixed(2)}',
          value.lookSpeed,
          GameSettings.minLookSpeed,
          GameSettings.maxLookSpeed,
          ((GameSettings.maxLookSpeed - GameSettings.minLookSpeed) / 0.05).round(),
          (v) => value.copyWith(lookSpeed: (v * 100).round() / 100),
        ),
        _slider(
          'Field of view',
          '${value.fov.round()}°',
          value.fov,
          GameSettings.minFov,
          GameSettings.maxFov,
          (GameSettings.maxFov - GameSettings.minFov).round(),
          (v) => value.copyWith(fov: v.roundToDouble()),
        ),
        if (sound.enabled)
          _slider(
            'Volume',
            percent(value.volume),
            value.volume,
            0.0,
            1.0,
            20,
            (v) => value.copyWith(volume: _hundredths(v)),
          ),
        if (sound.enabled && sound.music != null)
          _slider(
            'Music',
            percent(value.musicVolume),
            value.musicVolume,
            0.0,
            1.0,
            20,
            (v) => value.copyWith(musicVolume: _hundredths(v)),
          ),
        _switch('View bobbing', value.viewBob, (on) => value.copyWith(viewBob: on)),
        _switch('Show FPS', value.showFps, (on) => value.copyWith(showFps: on)),
        if (spec.sky.weather != null) _switch('Weather', value.weather, (on) => value.copyWith(weather: on)),
      ],
    );
  }

  static double _hundredths(double v) => (v * 100).round() / 100;

  Widget _slider(
    String label,
    String shown,
    double at,
    double min,
    double max,
    int divisions,
    GameSettings Function(double v) change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(shown, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      ),
      Slider(
        value: at,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (v) {
          final next = change(v);
          if (next != value) onChanged(next);
        },
      ),
    ],
  );

  Widget _switch(String label, bool on, GameSettings Function(bool on) change) => SwitchListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    title: Text(label),
    value: on,
    onChanged: (v) => onChanged(change(v)),
  );
}
