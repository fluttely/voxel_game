import 'package:flutter/material.dart';

import '../settings/settings_store.dart';
import '../spec/title_spec.dart';
import '../spec/voxel_game_spec.dart';
import '../world/world_save.dart';
import 'game_surface.dart';
import 'loading_screen.dart';
import 'title_choice.dart';
import 'title_screen.dart';
import 'voxel_game_widget.dart';

/// A game that opens on its title (`runVoxelGame(spec, menu: ...)`): the
/// [TitleScreen] until a world is picked, then that world in a
/// [VoxelGameWidget], and the title again when the game menu's Quit saves it
/// and leaves, or when the network refuses (the title then says why).
class VoxelGameHome extends StatefulWidget {
  /// The title [menu] of [spec], its worlds in [saves], its player's settings
  /// in [settings].
  const VoxelGameHome({
    super.key,
    required this.spec,
    required this.menu,
    required this.saves,
    required this.settings,
    this.hud,
    this.loading,
    this.onQuit,
  });

  /// The game.
  final VoxelGameSpec spec;

  /// Its title.
  final TitleSpec menu;

  /// Where its worlds are.
  final WorldSaves saves;

  /// Where the player's settings are.
  final SettingsStore settings;

  /// The HUD over a world; the default when null.
  final HudBuilder? hud;

  /// What shows while a world loads; the default when null.
  final LoadingBuilder? loading;

  /// The title's Quit, which closes the app; no Quit when null.
  final VoidCallback? onQuit;

  @override
  State<VoxelGameHome> createState() => _VoxelGameHomeState();
}

class _VoxelGameHomeState extends State<VoxelGameHome> {
  TitleChoice? _playing;
  String? _status;
  // A new key for each game, so a world played twice is two widgets.
  int _games = 0;

  void _play(TitleChoice choice) => setState(() {
    _playing = choice;
    _status = null;
    _games++;
  });

  void _back([String? status]) => setState(() {
    _playing = null;
    _status = status;
  });

  void _netFailed(Object error) => _back(switch (_playing!) {
    PlayWorld(:final hostPort) => 'Could not host on port $hostPort: another program has it.',
    JoinHost(:final address) => 'Could not join $address: no host answered.',
  });

  @override
  Widget build(BuildContext context) {
    final playing = _playing;
    if (playing == null) {
      return TitleScreen(
        spec: widget.spec,
        menu: widget.menu,
        saves: widget.saves,
        settings: widget.settings,
        onChoice: _play,
        onQuit: widget.onQuit,
        status: _status,
      );
    }
    return VoxelGameWidget(
      key: ValueKey(_games),
      spec: widget.spec,
      hud: widget.hud,
      loading: widget.loading,
      saves: widget.saves,
      settings: widget.settings,
      saveSlot: switch (playing) {
        PlayWorld(:final slot) => slot,
        JoinHost() => null,
      },
      hostPort: switch (playing) {
        PlayWorld(:final hostPort) => hostPort,
        JoinHost() => null,
      },
      join: switch (playing) {
        PlayWorld() => null,
        JoinHost(:final address) => address,
      },
      joinOptions: switch (playing) {
        PlayWorld() => const {},
        JoinHost(:final options) => options,
      },
      onQuit: _back,
      onNetError: _netFailed,
    );
  }
}
