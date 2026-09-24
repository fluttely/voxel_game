import 'package:flutter/material.dart';

import '../game/worlds.dart';
import '../player/player.dart';

/// Stage 30: the worlds under `worlds/` (name, mode, class, seed, dimension,
/// play time, last played), Play / Rename / Delete on the selection, and the
/// New World form (name, seed, Survival or Creative, class). Every action goes
/// through `Worlds`; [onStart] hands the chosen slot back to the title screen.
class WorldList extends StatefulWidget {
  const WorldList({super.key, required this.onStart, required this.onClosed, this.showForm = false});
  final void Function(String slot) onStart;
  final VoidCallback onClosed;
  final bool showForm;

  static const Map<String, String> classDesc = {
    'warrior': 'Strong and tough. Starts with a sword. Ability: Whirlwind hits everything around you.',
    'ranger': 'Fast bow shots. Starts with 48 arrows. Ability: Arrow Volley fires eight arrows at once.',
    'mage': 'Fire bolts that cost mana. Ability: Fire Nova burns every enemy near you.',
    'rogue': 'Quick daggers with bonus hits. Ability: Shadow Dash leaps you forward.',
  };

  @override
  State<WorldList> createState() => _WorldListState();
}

class _WorldListState extends State<WorldList> {
  List<WorldEntry> _entries = [];
  int _selected = -1;
  late bool _form = widget.showForm;
  final TextEditingController _name = TextEditingController(text: 'My World');
  final TextEditingController _seed = TextEditingController();
  final TextEditingController _rename = TextEditingController();
  bool _creative = false;
  String _class = 'warrior';

  static const TextStyle _white = TextStyle(color: Colors.white);
  static const Color _dim = Color.fromRGBO(191, 191, 204, 1);

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    _seed.dispose();
    _rename.dispose();
    super.dispose();
  }

  void refresh([String selectSlot = '']) {
    setState(() {
      _entries = Worlds.list();
      _selected = -1;
      for (var i = 0; i < _entries.length; i++) {
        if (_entries[i].slot == selectSlot || (selectSlot == '' && i == 0)) {
          _selected = i;
          break;
        }
      }
      _rename.text = _selected >= 0 ? _entries[_selected].name : '';
    });
  }

  WorldEntry? get _sel => _selected >= 0 && _selected < _entries.length ? _entries[_selected] : null;

  void _select(int i) => setState(() {
        _selected = i;
        _rename.text = _entries[i].name;
      });

  void _playSelected() {
    final e = _sel;
    if (e != null) widget.onStart(e.slot);
  }

  Future<void> _confirmDelete() async {
    final e = _sel;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete world'),
        content: Text("Delete '${e.name}'? Its save is gone for good."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      Worlds.delete(e.slot);
      refresh();
    }
  }

  String _rowText(WorldEntry e) {
    final dim = e.dimension == 1 ? 'Underworld' : 'Overworld';
    final cls = Player.classes[e.playerClass]?.name ?? e.playerClass;
    return '${e.name}   —   ${Worlds.modeLabel(e)} · $cls · seed ${e.seed} · $dim · played ${Worlds.playTimeLabel(e.playSeconds)} · last ${Worlds.lastPlayedLabel(e.lastPlayed)}';
  }

  Widget _button(String text, VoidCallback? cb, {double width = 110}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(width: width, height: 40, child: FilledButton.tonal(onPressed: cb, child: Text(text))),
      );

  Widget _list() => Container(
        decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, 0.35), border: Border.all(color: Colors.white24)),
        child: ListView.builder(
          itemCount: _entries.length,
          itemBuilder: (context, i) => GestureDetector(
            onDoubleTap: () {
              _select(i);
              _playSelected();
            },
            child: InkWell(
              onTap: () => _select(i),
              child: Container(
                color: i == _selected ? const Color.fromRGBO(90, 120, 200, 0.45) : null,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(_rowText(_entries[i]), style: const TextStyle(fontSize: 15, color: Colors.white)),
              ),
            ),
          ),
        ),
      );

  Widget _formColumn() {
    final c = Player.classes[_class]!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('New world', style: TextStyle(fontSize: 28, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('Name', style: TextStyle(fontSize: 14, color: Colors.white)),
          TextField(controller: _name, style: _white),
          const SizedBox(height: 8),
          const Text('Seed (empty = random)', style: TextStyle(fontSize: 14, color: Colors.white)),
          TextField(controller: _seed, style: _white),
          const SizedBox(height: 8),
          const Text('Game mode', style: TextStyle(fontSize: 14, color: Colors.white)),
          DropdownButton<bool>(
            value: _creative,
            isExpanded: true,
            dropdownColor: const Color.fromRGBO(20, 26, 41, 1),
            items: const [
              DropdownMenuItem(value: false, child: Text('Survival — hunger, damage, every block counts', style: _white)),
              DropdownMenuItem(value: true, child: Text('Creative — no damage, free blocks, F5 flies', style: _white)),
            ],
            onChanged: (v) => setState(() => _creative = v ?? false),
          ),
          const SizedBox(height: 8),
          const Text('Class', style: TextStyle(fontSize: 14, color: Colors.white)),
          Row(children: [
            for (final e in Player.classes.entries)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: SizedBox(
                    height: 40,
                    child: _class == e.key
                        ? FilledButton(onPressed: () => setState(() => _class = e.key), child: Text(e.value.name))
                        : OutlinedButton(onPressed: () => setState(() => _class = e.key), child: Text(e.value.name)),
                  ),
                ),
              ),
          ]),
          Text('${c.name} — HP ${c.hp.toInt()}, stamina ${c.stamina.toInt()}, mana ${c.mana.toInt()}\n${WorldList.classDesc[_class]}',
              style: const TextStyle(fontSize: 13, color: Color.fromRGBO(235, 235, 242, 1))),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () {
                final slot = Worlds.create(_name.text, _seed.text, _creative ? 'creative' : 'survival', _class);
                widget.onStart(slot);
              },
              child: const Text('Start'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color.fromRGBO(8, 10, 20, 0.86),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Worlds', style: TextStyle(fontSize: 34, color: Colors.white)),
                  const SizedBox(height: 8),
                  Expanded(child: SizedBox(width: double.infinity, child: _list())),
                  const SizedBox(height: 8),
                  Row(children: [
                    _button('Play', _sel == null ? null : _playSelected, width: 140),
                    _button('New world', () => setState(() => _form = !_form), width: 130),
                    _button('Delete', _sel == null ? null : _confirmDelete),
                    _button('Back', widget.onClosed),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    SizedBox(
                      width: 260,
                      child: TextField(controller: _rename, style: _white, decoration: const InputDecoration(hintText: 'new name')),
                    ),
                    const SizedBox(width: 8),
                    _button('Rename', () {
                      final e = _sel;
                      if (e != null && Worlds.rename(e.slot, _rename.text)) refresh(e.slot);
                    }),
                  ]),
                  const SizedBox(height: 6),
                  Text('${_entries.length} world${_entries.length == 1 ? '' : 's'} in ${Worlds.root}', style: const TextStyle(fontSize: 13, color: _dim)),
                ],
              ),
            ),
            if (_form) ...[
              const SizedBox(width: 24),
              Expanded(flex: 10, child: _formColumn()),
            ],
          ],
        ),
      ),
    );
  }
}
