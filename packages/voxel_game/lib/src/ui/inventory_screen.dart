import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:voxel_engine/content.dart';

import '../core/voxel_game.dart';
import 'item_icon.dart';
import 'screen_focus.dart';
import 'secondary_activate_intent.dart';

/// The bag and crafting: every slot (the hotbar last, as block sandboxes lay
/// it out) and, beside it, the recipes of [station] (`''` for the hand) with
/// what each needs, or the slots of an open [storage].
///
/// A click or a tap on a slot picks its stack up or puts the held one down;
/// a right-click or a long press takes half, or leaves one
/// (`PlayerEntity.clickSlot`, the held stack being the player's `carried`,
/// so a host's refusal can take it back). The held stack
/// follows the pointer (above a finger, which would hide it); one let go
/// outside the panel is thrown into the world, ahead of the player, as a
/// press of drop throws one. A tooltip says what the slot under the mouse
/// holds, or else what is held, from the item's row.
///
/// A pad and the keys work it through the focus (`FocusBridge`): each slot
/// takes it, the slot in hand first, and draws it; A (Enter, Space) is a
/// slot's click and X (the X key) its right-click
/// ([SecondaryActivateIntent]), through the same handlers. The held stack
/// and the tooltip then sit by the focused slot, as they would by a mouse
/// over it. A recipe is a list tile, crafted by A as by a tap.
///
/// The slots rebuild when the bag or the store changes, never every frame,
/// so a click is never lost to a rebuild under the pointer; only the held
/// stack and the tooltip follow the pointer.
class InventoryScreen extends StatefulWidget {
  /// The screen of [game] at [station], beside [storage] when one is open;
  /// [onClose] shuts it.
  const InventoryScreen({super.key, required this.game, required this.station, required this.onClose, this.storage});

  /// The game.
  final VoxelGame game;

  /// The station crafted at; `''` in the hand. With a [storage], the block
  /// that stores, named over its slots.
  final String station;

  /// The store open beside the bag (`VoxelGame.openStorage`), or null.
  final Inventory? storage;

  /// Called by the close button.
  final VoidCallback onClose;

  /// How far above a finger the held stack is drawn.
  static const double fingerLift = 56.0;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

/// Where the pointer last was, what kind it is, and the slot a mouse hovers;
/// or, [focus], the corner of the slot the focus is on, [over] while it is.
class _Pointer {
  const _Pointer(this.at, {required this.touch, this.over, this.focus = false});

  final Offset at;
  final bool touch;
  final (Inventory, int)? over;
  final bool focus;
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ValueNotifier<_Pointer?> _pointer = ValueNotifier(null);

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
    _pointer.dispose();
    widget.game.player.stowCarried();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// A pointer moved: what it is over is a mouse's hover, never the focus's.
  void _moved(PointerEvent e) {
    final p = _pointer.value;
    _pointer.value = _Pointer(
      e.localPosition,
      touch: e.kind == PointerDeviceKind.touch,
      over: p == null || p.focus ? null : p.over,
    );
  }

  /// The focus onto or off slot [i] of [inv], laid out at [slot]: onto it,
  /// the held stack and the tooltip go to its corner.
  void _focused(BuildContext slot, Inventory inv, int i, {required bool on}) {
    final p = _pointer.value;
    if (on) {
      final box = slot.findRenderObject()! as RenderBox;
      final corner = box.localToGlobal(box.size.topRight(Offset.zero));
      final at = (context.findRenderObject()! as RenderBox).globalToLocal(corner);
      _pointer.value = _Pointer(at, touch: false, over: (inv, i), focus: true);
    } else if (p != null && p.focus && p.over == (inv, i)) {
      _pointer.value = _Pointer(p.at, touch: false, focus: true);
    }
  }

  /// A mouse into or out of slot [i] of [inv]. A slot's event is in the
  /// slot's own space: the screen's is found from where it is on the screen.
  void _hover(Inventory inv, int i, PointerEvent e, {required bool inside}) {
    final at = (context.findRenderObject()! as RenderBox).globalToLocal(e.position);
    final over = _pointer.value?.over;
    if (inside) {
      _pointer.value = _Pointer(at, touch: false, over: (inv, i));
    } else if (over == (inv, i)) {
      _pointer.value = _Pointer(at, touch: false);
    }
  }

  void _click(Inventory inv, int i, {required bool one}) =>
      setState(() => widget.game.player.clickSlot(inv, i, one: one));

  /// The held stack, or one of it, let go outside the panel.
  void _throw({required bool one}) => setState(() => widget.game.player.throwCarried(one: one));

  Widget _stack(ItemStack? s, {double size = 44}) => SizedBox(
    width: size,
    height: size,
    child: s == null
        ? null
        : Stack(
            children: [
              Center(child: ItemIcon(widget.game.itemModel(s.id), size: size * 0.75)),
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
    return Builder(
      builder: (slot) => FocusableActionDetector(
        autofocus: selected,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _click(inv, i, one: false)),
          SecondaryActivateIntent: CallbackAction<SecondaryActivateIntent>(onInvoke: (_) => _click(inv, i, one: true)),
        },
        onFocusChange: (on) => _focused(slot, inv, i, on: on),
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return MouseRegion(
              onEnter: (e) => _hover(inv, i, e, inside: true),
              onExit: (e) => _hover(inv, i, e, inside: false),
              child: GestureDetector(
                onTap: () => _click(inv, i, one: false),
                onSecondaryTap: () => _click(inv, i, one: true),
                onLongPress: () => _click(inv, i, one: true),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: focused ? ScreenFocus.fill : Colors.black38,
                    border: Border.all(color: selected ? Colors.white : Colors.white24),
                  ),
                  // Drawn over the slot, so the ring does not move it.
                  foregroundDecoration: focused
                      ? const BoxDecoration(border: Border.fromBorderSide(ScreenFocus.ring))
                      : null,
                  child: _stack(inv.slots[i]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// [inv]'s slots [from] to [to], [width] a row.
  List<Widget> _rows(Inventory inv, int from, int to, int width) => [
    for (var row = from; row < to; row += width)
      Row(mainAxisSize: MainAxisSize.min, children: [for (var i = row; i < row + width && i < to; i++) _slot(inv, i)]),
  ];

  String _blockName(String id) => widget.game.blocks[widget.game.blocks.indexOf(id)].name;

  String _itemName(String id) => widget.game.items.has(id) ? widget.game.items[id].name : id;

  /// What [s] is, line by line, read off its item's row.
  List<String> _describe(ItemStack s) {
    final game = widget.game;
    final t = game.items[s.id];
    final food = t.food, armor = t.armor, tool = t.tool, block = t.block;
    final name = tool == null ? '' : '${tool[0].toUpperCase()}${tool.substring(1)}';
    final eaten = [
      if (food != null && food.hunger > 0) 'Food +${food.hunger}',
      if (food != null && food.heal > 0) 'Heals ${food.heal.toStringAsFixed(food.heal % 1 == 0 ? 0 : 1)}',
      if (food?.effect case final e?)
        '${game.spec.effects.firstWhere((x) => x.id == e).name} ${food!.seconds.toStringAsFixed(0)} s',
    ];
    return [
      t.name,
      if (tool != null) t.tier > 0 ? '$name, tier ${t.tier}' : name,
      if (t.damage > 1 || s.bonus > 0) 'Damage ${t.damage}${s.bonus > 0 ? ' +${s.bonus}' : ''}',
      if (t.durability > 0) 'Uses ${s.dur >= 0 ? s.dur : t.durability} / ${t.durability}',
      if (eaten.isNotEmpty) eaten.join(' · '),
      if (armor != null) 'Worn: ${armor.slot}, armour ${armor.points}',
      if (block != null && block != s.id) 'Places ${_blockName(block)}',
    ];
  }

  Widget _tooltip(ItemStack s) {
    final lines = _describe(s);
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xF0101418), borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lines.first, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            for (final l in lines.skip(1)) Text(l, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  /// The held stack under the pointer and the tooltip beside it.
  Widget _overPointer(BuildContext context, _Pointer? p, Widget? _) {
    if (p == null) return const SizedBox.shrink();
    final held = widget.game.player.carried;
    final over = p.over;
    final described = (over == null ? null : over.$1.slots[over.$2]) ?? held;
    final lift = p.touch ? InventoryScreen.fingerLift : 0.0;
    return Stack(
      children: [
        if (described != null)
          Positioned.fill(
            child: CustomSingleChildLayout(delegate: _Beside(p.at - Offset(0, lift)), child: _tooltip(described)),
          ),
        if (held != null) Positioned(left: p.at.dx - 22, top: p.at.dy - 22 - lift, child: _stack(held)),
      ],
    );
  }

  Widget _recipes() {
    final game = widget.game;
    final recipes = game.recipes.available(widget.station);
    return SizedBox(
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
                    title: Text('${_itemName(r.result)} x${r.count}'),
                    subtitle: Text(
                      r.ingredients.entries
                          .map((e) => '${_itemName(e.key)} ${_inv.countOf(e.key)}/${e.value}')
                          .join(', '),
                    ),
                    enabled: game.recipes.canCraft(r, _inv),
                    onTap: () => game.player.craft(r),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hotbar = _inv.hotbarSize, cap = _inv.capacity;
    final storage = widget.storage;
    final side = storage != null || widget.station.isNotEmpty ? _blockName(widget.station) : 'Crafting';
    const heading = TextStyle(fontSize: 18);
    final panel = Material(
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
                const SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Inventory', style: heading),
                  ),
                ),
                ..._rows(_inv, hotbar, cap, hotbar),
                const SizedBox(height: 10),
                ..._rows(_inv, 0, hotbar, hotbar),
              ],
            ),
            const SizedBox(width: 24),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(side, style: heading),
                      const SizedBox(width: 12),
                      IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close), tooltip: 'Close (E)'),
                    ],
                  ),
                ),
                if (storage != null) ..._rows(storage, 0, storage.capacity, hotbar) else _recipes(),
              ],
            ),
          ],
        ),
      ),
    );
    return Listener(
      onPointerDown: _moved,
      onPointerMove: _moved,
      onPointerHover: _moved,
      child: Stack(
        children: [
          // Outside the panel: a stack let go here is thrown into the world.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _throw(one: false),
              onSecondaryTap: () => _throw(one: true),
              onLongPress: () => _throw(one: true),
              child: const ColoredBox(color: Colors.black54),
            ),
          ),
          // Shrunk to fit a phone, never grown past its size.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: panel),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder(valueListenable: _pointer, builder: _overPointer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays a tooltip out below and right of [at], kept on the screen.
class _Beside extends SingleChildLayoutDelegate {
  const _Beside(this.at);

  final Offset at;

  static const double _gap = 16.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = at.dx + _gap;
    var y = at.dy + _gap;
    if (x + childSize.width > size.width) x = at.dx - _gap - childSize.width;
    if (y + childSize.height > size.height) y = at.dy - _gap - childSize.height;
    return Offset(x.clamp(0.0, size.width), y.clamp(0.0, size.height));
  }

  @override
  bool shouldRelayout(_Beside old) => old.at != at;
}
