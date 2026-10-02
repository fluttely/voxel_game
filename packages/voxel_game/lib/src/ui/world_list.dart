import 'package:flutter/material.dart';

import '../world/world_info.dart';
import '../world/world_save.dart';

/// The worlds under [saves], the last played first: a row each (its name, its
/// mode, its seed, how long it has been played and when last), Play, Rename
/// and Delete on the one selected, and New world, a form for a name, a seed
/// (any text, `WorldSaves.seedOf`) and, with [modes], survival or creative.
/// A world made is played at once. Every change goes through [saves].
class WorldList extends StatefulWidget {
  /// The worlds of [saves]; [onPlay] takes the slot to play, [onBack] leaves.
  const WorldList({super.key, required this.saves, required this.onPlay, required this.onBack, this.modes = true});

  /// Where the worlds are.
  final WorldSaves saves;

  /// Whether a new world picks its `WorldMode`.
  final bool modes;

  /// Plays the world in this slot.
  final ValueChanged<String> onPlay;

  /// Back to the menu.
  final VoidCallback onBack;

  /// How long a world has been played: `45 s`, `12 min`, `3 h 05 min`.
  static String playTimeLabel(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')} min';
  }

  /// When, to the minute: `2026-10-02 14:03`.
  static String dateLabel(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// The line under a world's name.
  static String detailsOf(WorldInfo w) => [
    if (w.mode case final m?)
      switch (m) {
        WorldMode.survival => 'Survival',
        WorldMode.creative => 'Creative',
      },
    'seed ${w.seed}',
    if (w.lastPlayed case final at?) ...['played ${playTimeLabel(w.playTime)}', 'last ${dateLabel(at)}'] else 'new',
  ].join(' · ');

  @override
  State<WorldList> createState() => _WorldListState();
}

class _WorldListState extends State<WorldList> {
  late List<WorldInfo> _worlds = widget.saves.worlds();
  String? _selected;
  bool _making = false;
  final TextEditingController _name = TextEditingController(text: 'New world');
  final TextEditingController _seed = TextEditingController();
  WorldMode _mode = WorldMode.survival;

  @override
  void initState() {
    super.initState();
    _selected = _worlds.firstOrNull?.slot;
  }

  @override
  void dispose() {
    _name.dispose();
    _seed.dispose();
    super.dispose();
  }

  WorldInfo? get _selection => _worlds.where((w) => w.slot == _selected).firstOrNull;

  void _refresh(String? select) => setState(() {
    _worlds = widget.saves.worlds();
    _selected = select ?? _worlds.firstOrNull?.slot;
  });

  void _create() {
    final w = widget.saves.create(_name.text, seed: WorldSaves.seedOf(_seed.text), mode: widget.modes ? _mode : null);
    widget.onPlay(w.slot);
  }

  Future<void> _rename(WorldInfo w) async {
    final name = await showDialog<String>(context: context, builder: (context) => _RenameDialog(w.name));
    if (name == null || name.trim().isEmpty) return;
    widget.saves.rename(w.slot, name);
    _refresh(w.slot);
  }

  Future<void> _delete(WorldInfo w) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete world'),
        content: Text("Delete '${w.name}'? It is gone for good."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true) return;
    widget.saves.delete(w.slot);
    _refresh(null);
  }

  @override
  Widget build(BuildContext context) => _making ? _form() : _list();

  Widget _list() {
    final sel = _selection;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: _worlds.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No worlds yet.', textAlign: TextAlign.center),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final w in _worlds)
                      ListTile(
                        dense: true,
                        selected: w.slot == _selected,
                        selectedTileColor: Colors.white12,
                        title: Text(w.name),
                        subtitle: Text(WorldList.detailsOf(w)),
                        onTap: () => setState(() => _selected = w.slot),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            FilledButton(onPressed: sel == null ? null : () => widget.onPlay(sel.slot), child: const Text('Play')),
            OutlinedButton(onPressed: () => setState(() => _making = true), child: const Text('New world')),
            OutlinedButton(onPressed: sel == null ? null : () => _rename(sel), child: const Text('Rename')),
            OutlinedButton(onPressed: sel == null ? null : () => _delete(sel), child: const Text('Delete')),
            OutlinedButton(onPressed: widget.onBack, child: const Text('Back')),
          ],
        ),
      ],
    );
  }

  Widget _form() => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _seed,
          decoration: const InputDecoration(
            labelText: 'Seed',
            hintText: 'a number or any text; empty for a random one',
          ),
        ),
        if (widget.modes) ...[
          const SizedBox(height: 12),
          SegmentedButton<WorldMode>(
            segments: const [
              ButtonSegment(value: WorldMode.survival, label: Text('Survival')),
              ButtonSegment(value: WorldMode.creative, label: Text('Creative')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.single),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(onPressed: _name.text.trim().isEmpty ? null : _create, child: const Text('Create')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => setState(() => _making = false), child: const Text('Cancel')),
          ],
        ),
      ],
    ),
  );
}

/// Asks for a world's new name; pops it, or nothing when cancelled. It owns
/// its field, which must outlive the dialog's closing animation.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog(this.name);

  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _field = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename world'),
    content: TextField(controller: _field, autofocus: true, onSubmitted: (v) => Navigator.of(context).pop(v)),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.of(context).pop(_field.text), child: const Text('Rename')),
    ],
  );
}
