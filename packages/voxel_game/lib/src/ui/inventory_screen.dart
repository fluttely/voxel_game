import 'package:flutter/material.dart';
import 'package:voxel_engine/content.dart';

import '../core/voxel_game.dart';

/// The bag and crafting: every slot (the hotbar last, as block sandboxes lay
/// it out), a stack on the cursor to move between slots, and the recipes of
/// [station] (`''` for the hand) with what each needs; or, with a [storage]
/// open, its slots above the bag instead of the recipes. Click a slot to pick
/// up or put down; right-click to take or leave one.
///
/// It rebuilds when the bag or the store changes, never every frame, so a
/// click is never lost to a rebuild under the pointer.
class InventoryScreen extends StatefulWidget {
  /// The screen of [game] at [station], beside [storage] when one is open;
  /// [onClose] shuts it.
  const InventoryScreen({super.key, required this.game, required this.station, required this.onClose, this.storage});

  /// The game.
  final VoxelGame game;

  /// The station crafted at; `''` in the hand. With a [storage], the block
  /// that stores, named in the title.
  final String station;

  /// The store open beside the bag (`VoxelGame.openStorage`), or null.
  final Inventory? storage;

  /// Called by the close button.
  final VoidCallback onClose;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  ItemStack? _cursor;

  Inventory get _inv => widget.game.player.inventory;

  @override
  void initState() {
    super.initState();
    _inv.listeners.add(_changed);
    widget.storage?.listeners.add(_changed);
  }

  @override
  void didUpdateWidget(InventoryScreen old) {
    super.didUpdateWidget(old);
    if (old.storage == widget.storage) return;
    old.storage?.listeners.remove(_changed);
    widget.storage?.listeners.add(_changed);
  }

  @override
  void dispose() {
    _inv.listeners.remove(_changed);
    widget.storage?.listeners.remove(_changed);
    final held = _cursor;
    // Nothing is lost on the cursor when the screen shuts.
    if (held != null && !_inv.addStack(held)) _inv.add(held.id, held.count);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _click(Inventory inv, int i, {required bool one}) {
    final slot = inv.slots[i];
    final held = _cursor;
    setState(() {
      if (held == null) {
        if (slot != null) _cursor = inv.takeFromSlot(i, one ? (slot.count + 1) ~/ 2 : slot.count);
        return;
      }
      if (slot == null) {
        final put = one ? 1 : held.count;
        inv.setSlot(i, held.copy()..count = put);
        held.count -= put;
        if (held.count <= 0) _cursor = null;
        return;
      }
      if (slot.id == held.id && slot.bonus == held.bonus && slot.dur < 0 && held.dur < 0) {
        final room = inv.stackSize(slot.id) - slot.count;
        final put = (one ? 1 : held.count).clamp(0, room);
        slot.count += put;
        held.count -= put;
        if (held.count <= 0) _cursor = null;
        inv.emitChanged();
        return;
      }
      // Different items: swap the cursor with the slot.
      inv.setSlot(i, held);
      _cursor = slot;
    });
  }

  Color _color(String id) {
    final t = widget.game.items[id];
    return Color.fromARGB(255, (t.r * 255).round(), (t.g * 255).round(), (t.b * 255).round());
  }

  Widget _stack(ItemStack? s, {double size = 44}) => SizedBox(
    width: size,
    height: size,
    child: s == null
        ? null
        : Stack(
            children: [
              Center(
                child: Container(width: size * 0.55, height: size * 0.55, color: _color(s.id)),
              ),
              if (s.count > 1)
                Positioned(
                  right: 3,
                  bottom: 1,
                  child: Text(
                    '${s.count}',
                    style: const TextStyle(fontSize: 12, shadows: [Shadow(offset: Offset(1, 1))]),
                  ),
                ),
            ],
          ),
  );

  Widget _slot(Inventory inv, int i) {
    final selected = inv == _inv && i == widget.game.player.selectedSlot;
    return Tooltip(
      message: inv.isEmptySlot(i) ? '' : widget.game.items[inv.idAt(i)].name,
      child: GestureDetector(
        onTap: () => _click(inv, i, one: false),
        onSecondaryTap: () => _click(inv, i, one: true),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.black38,
            border: Border.all(color: selected ? Colors.white : Colors.white24),
          ),
          child: _stack(inv.slots[i]),
        ),
      ),
    );
  }

  /// [inv]'s slots [from] to [to], [width] a row.
  List<Widget> _rows(Inventory inv, int from, int to, int width) => [
    for (var row = from; row < to; row += width)
      Row(mainAxisSize: MainAxisSize.min, children: [for (var i = row; i < row + width && i < to; i++) _slot(inv, i)]),
  ];

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final hotbar = _inv.hotbarSize, cap = _inv.capacity;
    final storage = widget.storage;
    final recipes = game.recipes.available(widget.station);
    final title = widget.station.isEmpty ? 'Inventory' : game.blocks[game.blocks.indexOf(widget.station)].name;
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        // Its own Material, so the recipes' tiles draw whether or not the game
        // put a Scaffold above the widget.
        child: Material(
          color: const Color(0xEE1E2430),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 12),
                        IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close), tooltip: 'Close (E)'),
                      ],
                    ),
                    if (storage != null) ...[
                      ..._rows(storage, 0, storage.capacity, hotbar),
                      const SizedBox(height: 10),
                    ],
                    ..._rows(_inv, hotbar, cap, hotbar),
                    const SizedBox(height: 10),
                    ..._rows(_inv, 0, hotbar, hotbar),
                    const SizedBox(height: 8),
                    Row(children: [const Text('Cursor: '), _stack(_cursor, size: 32)]),
                  ],
                ),
                if (storage == null) const SizedBox(width: 16),
                if (storage == null)
                  SizedBox(
                    width: 260,
                    height: 360,
                    child: recipes.isEmpty
                        ? const Text('Nothing to craft here')
                        : ListView(
                            children: [
                              for (final r in recipes)
                                ListTile(
                                  dense: true,
                                  leading: _stack(ItemStack(r.result, r.count), size: 32),
                                  title: Text(
                                    '${game.items.has(r.result) ? game.items[r.result].name : r.result} x${r.count}',
                                  ),
                                  subtitle: Text(
                                    r.ingredients.entries
                                        .map(
                                          (e) =>
                                              '${game.items.has(e.key) ? game.items[e.key].name : e.key} ${_inv.countOf(e.key)}/${e.value}',
                                        )
                                        .join(', '),
                                  ),
                                  enabled: game.recipes.canCraft(r, _inv),
                                  onTap: () => game.recipes.craft(r, _inv),
                                ),
                            ],
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
