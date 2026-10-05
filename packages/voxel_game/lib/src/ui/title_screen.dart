import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sound_recipes/sound_recipes.dart';

import '../audio/game_music.dart';
import '../settings/game_settings.dart';
import '../settings/settings_store.dart';
import '../spec/music_spec.dart';
import '../spec/title_spec.dart';
import '../spec/voxel_game_spec.dart';
import '../world/world_save.dart';
import 'credits_roll.dart';
import 'settings_panel.dart';
import 'title_choice.dart';
import 'world_list.dart';

enum _Panel { menu, worlds, multiplayer, settings, credits }

/// The title [menu] declares, with no game running: Play (the [WorldList]),
/// Multiplayer (host a world of the list, or join an address), Settings (the
/// [SettingsPanel], read from and written to [settings] directly), Credits,
/// and Quit when [onQuit] is given. What the player picks goes to [onChoice];
/// [status] says why the last pick came back (a host that did not answer).
/// Under it plays the track [menu] names (`TitleSpec.music`), on an audio
/// device of its own that closes with the screen, before a world opens its
/// own.
///
/// Escape, or Back, leaves a panel for the menu. A keyboard moves between
/// the buttons with Tab and presses one with Enter or Space; a pad cannot
/// (`KL-013`).
class TitleScreen extends StatefulWidget {
  /// The title of a game of [spec].
  const TitleScreen({
    super.key,
    required this.spec,
    required this.menu,
    required this.saves,
    required this.settings,
    required this.onChoice,
    this.onQuit,
    this.status,
  });

  /// The game.
  final VoxelGameSpec spec;

  /// The title, declared.
  final TitleSpec menu;

  /// The worlds.
  final WorldSaves saves;

  /// The player's settings, the file the game reads them from.
  final SettingsStore settings;

  /// Takes the world to play, host or join.
  final ValueChanged<TitleChoice> onChoice;

  /// Quit; no Quit when null.
  final VoidCallback? onQuit;

  /// A line under the menu, or none.
  final String? status;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  _Panel _panel = _Panel.menu;
  late GameSettings _settings = widget.settings.read(GameSettings.of(widget.spec));
  Timer? _settingsWrite;
  final TextEditingController _address = TextEditingController();
  String? _host;
  // What the join form picked of the options it offers (`WorldOption.join`).
  late final Map<String, String> _joinOptions = {
    for (final o in widget.menu.worldOptions)
      if (o.join) o.id: o.first,
  };
  // Asked once, when Multiplayer first opens.
  late final Future<List<NetworkInterface>> _interfaces = NetworkInterface.list(type: InternetAddressType.IPv4);

  SoundBank? _bank;
  GameMusic? _music;

  static final RegExp _addressPattern = RegExp(r'^[A-Za-z0-9.\-]+(:\d{1,5})?$');

  @override
  void initState() {
    super.initState();
    final track = widget.menu.music;
    if (track == null) return;
    final music = widget.spec.sounds.music;
    if (music == null || !music.tracks.containsKey(track)) {
      throw ArgumentError.value(track, 'TitleSpec.music', 'no such track');
    }
    if (widget.spec.sounds.enabled) unawaited(_play(music, track));
  }

  // The audio device alone: the title plays no sound but its music.
  Future<void> _play(MusicSpec music, String track) async {
    final bank = SoundBank(recipes: const {});
    await bank.init();
    if (!mounted) return bank.dispose();
    _bank = bank;
    _music = GameMusic(music, _settings)..play(track);
  }

  @override
  void dispose() {
    _flushSettings();
    _address.dispose();
    _music?.close();
    _bank?.dispose();
    super.dispose();
  }

  // A slider writes once it comes to rest, as in the game.
  void _changeSettings(GameSettings value) {
    setState(() => _settings = value);
    _music?.follow(value);
    _settingsWrite?.cancel();
    _settingsWrite = Timer(const Duration(milliseconds: 500), () => widget.settings.write(value));
  }

  void _flushSettings() {
    if (_settingsWrite?.isActive ?? false) widget.settings.write(_settings);
    _settingsWrite?.cancel();
  }

  void _open(_Panel panel) {
    if (_panel == _Panel.settings) _flushSettings();
    setState(() => _panel = panel);
  }

  @override
  Widget build(BuildContext context) {
    // Material under it all: the menu's text is not a stray Text's.
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape || _panel == _Panel.menu) {
            return KeyEventResult.ignored;
          }
          _open(_Panel.menu);
          return KeyEventResult.handled;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.menu.background?.call(context) ?? const _Dusk(),
            SafeArea(
              child: Center(
                child: switch (_panel) {
                  _Panel.menu => _menu(),
                  _Panel.worlds => _framed(
                    'Worlds',
                    WorldList(
                      saves: widget.saves,
                      modes: widget.menu.modes,
                      options: widget.menu.worldOptions,
                      onPlay: (slot) => widget.onChoice(PlayWorld(slot)),
                      onBack: () => _open(_Panel.menu),
                    ),
                    width: 560,
                  ),
                  _Panel.multiplayer => _framed('Multiplayer', _multiplayer()),
                  _Panel.settings => _framed(
                    'Settings',
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            child: SettingsPanel(spec: widget.spec, value: _settings, onChanged: _changeSettings),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(onPressed: () => _open(_Panel.menu), child: const Text('Done')),
                      ],
                    ),
                  ),
                  _Panel.credits => _framed(
                    null,
                    CreditsRoll(lines: widget.menu.credits, onBack: () => _open(_Panel.menu)),
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu() {
    const shadow = [Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 4)];
    final menu = widget.menu, quit = widget.onQuit;
    Widget button(String label, VoidCallback onPressed) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FilledButton(onPressed: onPressed, child: Text(label)),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              menu.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, shadows: shadow),
            ),
            if (menu.tagline case final t?)
              Text(
                t,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, shadows: shadow),
              ),
            const SizedBox(height: 20),
            button('Play', () => _open(_Panel.worlds)),
            if (menu.multiplayer) button('Multiplayer', () => _open(_Panel.multiplayer)),
            button('Settings', () => _open(_Panel.settings)),
            if (menu.credits.isNotEmpty) button('Credits', () => _open(_Panel.credits)),
            if (quit != null) button('Quit', quit),
            if (widget.status case final s?) ...[
              const SizedBox(height: 8),
              Text(
                s,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orangeAccent, shadows: shadow),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _multiplayer() {
    final worlds = widget.saves.worlds();
    final host = worlds.any((w) => w.slot == _host) ? _host : worlds.firstOrNull?.slot;
    final address = _address.text.trim();
    final port = widget.menu.port;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Host a world on port $port', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (worlds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No worlds yet: make one under Play.'),
            )
          else
            DropdownButton<String>(
              value: host,
              isExpanded: true,
              items: [for (final w in worlds) DropdownMenuItem(value: w.slot, child: Text(w.name))],
              onChanged: (slot) => setState(() => _host = slot),
            ),
          _Addresses(_interfaces),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: host == null ? null : () => widget.onChoice(PlayWorld(host, hostPort: port)),
            child: const Text('Host'),
          ),
          const SizedBox(height: 20),
          const Text('Join a world', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(
            controller: _address,
            decoration: InputDecoration(labelText: 'Address', hintText: '192.168.0.10 or 192.168.0.10:$port'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _join(),
          ),
          for (final o in widget.menu.worldOptions)
            if (o.join)
              DropdownButtonFormField<String>(
                initialValue: _joinOptions[o.id],
                decoration: InputDecoration(labelText: o.label),
                items: [for (final c in o.choices.entries) DropdownMenuItem(value: c.key, child: Text(c.value))],
                onChanged: (v) => setState(() => _joinOptions[o.id] = v!),
              ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _addressPattern.hasMatch(address) ? _join : null, child: const Text('Join')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _open(_Panel.menu), child: const Text('Back')),
        ],
      ),
    );
  }

  void _join() {
    final address = _address.text.trim();
    if (!_addressPattern.hasMatch(address)) return;
    widget.onChoice(
      JoinHost(address.contains(':') ? address : '$address:${widget.menu.port}', options: Map.of(_joinOptions)),
    );
  }

  Widget _framed(String? title, Widget child, {double width = 440}) => Padding(
    padding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Material(
        color: const Color(0xEE1E2430),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 8),
              ],
              Flexible(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Where others reach this machine: its IPv4 addresses on the local network.
class _Addresses extends StatelessWidget {
  const _Addresses(this.interfaces);

  final Future<List<NetworkInterface>> interfaces;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<NetworkInterface>>(
    future: interfaces,
    builder: (context, snap) {
      final found = [for (final i in snap.data ?? const <NetworkInterface>[]) ...i.addresses.map((a) => a.address)];
      if (found.isEmpty) return const SizedBox.shrink();
      return Text('Others join at ${found.join(' or ')}', style: const TextStyle(fontSize: 13, color: Colors.white70));
    },
  );
}

/// The menu's default ground: a dusk sky, deep blue above a warm horizon.
class _Dusk extends StatelessWidget {
  const _Dusk();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0E1A3A), Color(0xFF2E4A7A), Color(0xFFC07A50)],
        stops: [0.0, 0.65, 1.0],
      ),
    ),
  );
}
