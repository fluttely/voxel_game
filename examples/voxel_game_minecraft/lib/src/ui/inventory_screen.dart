import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../core/blocks.dart';
import '../core/items.dart';
import '../core/recipes.dart';
import '../game/game.dart';
import '../game/game_state.dart';
import '../game/inventory.dart';
import '../game/net.dart';
import '../game/sfx.dart';
import 'hud.dart';

/// Inventory grid + crafting list. Click a slot to pick up a stack, click again
/// to drop or swap; right click places one. Recipes on the right craft on click.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.game});
  final Game game;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  ItemStack? _cursor;

  /// Stage 25: whether the cursor stack was picked out of the chest grid (else
  /// out of the bag), sent with every chest edit so the host can account for
  /// the items that enter the chest.
  bool _cursorFromChest = false;
  Offset _mouse = Offset.zero;

  /// The cursor now holds a different item, or more of the same, than [had].
  bool _cursorGrew(ItemStack? had) {
    final c = _cursor;
    return (c?.id ?? '') != (had?.id ?? '') || (c?.count ?? 0) > (had?.count ?? 0);
  }
  final PanelScroll _recipeScroll = PanelScroll();
  late final PanelScrollInput _scrollInput = PanelScrollInput(() => _recipeScroll, () => _k);

  /// Where the recipe list is drawn, in panel space; its rows are recorded in
  /// the scrolled content's space ([PanelScroll.toContent]).
  Rect _recipeBody = Rect.zero;
  final List<Rect> _slotRects = [];
  final List<Rect> _chestRects = [];
  final List<(Rect, Recipe)> _recipeRects = [];

  /// The recipe under [mp] (panel space), if the list shows it there.
  Recipe? _recipeAt(Offset mp) {
    if (!_recipeBody.contains(mp)) return null;
    final cp = _recipeScroll.toContent(mp);
    for (final pair in _recipeRects) {
      if (pair.$1.contains(cp)) return pair.$2;
    }
    return null;
  }
  double _k = 1.0;
  Offset _origin = Offset.zero;

  Game get game => widget.game;

  /// Maps a viewport position into the panel's virtual 1120x600 space.
  Offset _toPanel(Offset p) => Offset((p.dx - _origin.dx) / _k, (p.dy - _origin.dy) / _k);

  @override
  void dispose() {
    final c = _cursor;
    if (c != null) game.player.inventory.add(c.id, c.count);
    if (game.chest != null) Net.instance.closeChest(game.chestPos);
    super.dispose();
  }

  void _click(Offset mp, bool right) {
    for (var i = 0; i < _slotRects.length; i++) {
      if (_slotRects[i].contains(mp)) {
        final had = _cursor?.copy();
        _clickSlot(game.player.inventory, i, right);
        if (_cursorGrew(had)) _cursorFromChest = false;
        return;
      }
    }
    final chest = game.chest;
    if (chest != null) {
      for (var i = 0; i < _chestRects.length; i++) {
        if (_chestRects[i].contains(mp)) {
          final had = _cursor?.copy();
          final fromBag = !_cursorFromChest;
          _clickSlot(chest, i, right);
          if (_cursorGrew(had)) _cursorFromChest = true;
          // Stage 25: one slot plus where the items came from; the host checks it.
          Net.instance.chestSlotChanged(game.chestPos, i, chest.slots[i], fromBag);
          return;
        }
      }
    }
    if (_cursor == null) {
      final recipe = _recipeAt(mp);
      if (recipe != null) {
        Sfx.play('click', -6.0);
        game.player.craft(recipe);
        return;
      }
    }
    // Click outside with a cursor stack: drop it into the world.
    final c = _cursor;
    if (c != null && !right) {
      game.spawnDrop(game.player.position + vm.Vector3(0, 1.4, 0), c.id, c.count, vm.Vector3(0, 2, 0), 1.5);
      _cursor = null;
    }
  }

  void _clickSlot(Inventory inv, int i, bool right) {
    final slot = inv.slots[i];
    final cur = _cursor;
    if (cur == null) {
      if (slot == null) return;
      if (right) {
        final half = (slot.count / 2.0).ceil();
        _cursor = inv.takeFromSlot(i, half);
      } else {
        _cursor = inv.takeFromSlot(i, slot.count);
      }
      return;
    }
    if (slot == null) {
      if (right) {
        inv.setSlot(i, ItemStack(cur.id, 1, bonus: cur.bonus));
        cur.count -= 1;
      } else {
        inv.setSlot(i, cur);
        _cursor = null;
      }
    } else if (slot.id == cur.id) {
      final room = Items.stackSize(slot.id) - slot.count;
      final move = (right ? 1 : cur.count).clamp(0, room);
      slot.count += move;
      cur.count -= move;
      inv.emitChanged();
    } else {
      final tmp = slot.copy();
      inv.setSlot(i, cur);
      _cursor = tmp;
    }
    final c2 = _cursor;
    if (c2 != null && c2.count <= 0) _cursor = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerHover: (e) => setState(() => _mouse = _toPanel(e.localPosition)),
      onPointerDown: (e) => setState(() {
        _mouse = _toPanel(e.localPosition);
        _scrollInput.down(e);
        // A finger may be starting a scroll: it acts when it lifts.
        if (e.kind != PointerDeviceKind.touch) _click(_mouse, e.buttons & kSecondaryMouseButton != 0);
      }),
      onPointerMove: (e) => setState(() {
        _mouse = _toPanel(e.localPosition);
        _scrollInput.move(e);
      }),
      onPointerUp: (e) => setState(() {
        if (e.kind == PointerDeviceKind.touch && !_scrollInput.dragged) _click(_toPanel(e.localPosition), false);
      }),
      onPointerSignal: (e) => setState(() => _scrollInput.signal(e)),
      onPointerPanZoomUpdate: (e) => setState(() => _scrollInput.panZoom(e)),
      child: CustomPaint(
        painter: _InventoryPainter(this),
        size: Size.infinite,
      ),
    );
  }
}

class _InventoryPainter extends CustomPainter {
  _InventoryPainter(this.s) : super(repaint: s.game.frame);
  final _InventoryScreenState s;

  String _describe(String id) {
    final d = Items.def(id);
    var text = d.name;
    switch (d.kind) {
      case ItemKind.tool:
        text += '  —  ${const ['', 'Pickaxe', 'Axe', 'Shovel', 'Sword', 'Hoe'][d.tool.index]} tool, tier ${d.tier}, damage ${d.damage}';
      case ItemKind.weapon:
        text += '  —  damage ${d.damage} (${d.style})';
      case ItemKind.food:
        text += '  —  food +${d.hunger}, heal ${d.heal.toInt()}  [H to eat]';
      case ItemKind.equipment:
        text += '  —  ${d.armor > 0 ? 'armor +${d.armor} (kept in inventory)' : 'hold G in the air to glide'}';
      case ItemKind.block:
        text += '  —  block';
      case ItemKind.material:
        break;
    }
    return text;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final game = s.game;
    final player = game.player;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color.fromRGBO(0, 0, 0, 0.55));
    // The layout is authored at 1600x900 (the Godot POC's window); scale it to fit.
    final k = ((size.width - 40) / 1120).clamp(0.3, 1.0).toDouble().clamp(0.0, ((size.height - 40) / 600).clamp(0.3, 1.0));
    s._k = k;
    s._origin = Offset((size.width - 1120 * k) / 2, (size.height - 600 * k) / 2);
    canvas.save();
    canvas.translate(s._origin.dx, s._origin.dy);
    canvas.scale(k);
    final panel = const Rect.fromLTWH(0, 0, 1120, 600);
    canvas.drawRect(panel, Paint()..color = const Color.fromRGBO(31, 31, 38, 0.96));
    canvas.drawRect(panel, Paint()..color = const Color.fromRGBO(153, 153, 166, 1)..style = PaintingStyle.stroke..strokeWidth = 2);
    final title = const {'': 'Inventory', 'crafting_table': 'Crafting Table', 'furnace': 'Furnace', 'chest': 'Chest', 'brewing_stand': 'Brewing Stand'}[game.station]!;
    Hud.text(canvas, title, panel.topLeft + const Offset(20, 34), size: 24);
    Hud.text(canvas, 'Click: pick / place   Right click: one   Esc / E: close', panel.topLeft + const Offset(20, 58), size: 13, color: const Color.fromRGBO(179, 179, 179, 1));

    // Player stats column
    final sx = panel.left + 20;
    final sy = panel.top + 90;
    final gs = GameState.instance;
    final lines = [
      '${player.classDef.name}  Level ${player.level}',
      'HP ${player.hp.toInt()}/${player.maxHp.toInt()}   Mana ${player.mana.toInt()}/${player.maxMana.toInt()}',
      'XP ${player.xp} / ${player.xpToNext()}',
      'Armor ${player.armor}',
      'Ability: ${player.classDef.ability} [R]',
      '',
      'Mined ${gs.blocksMined}   Placed ${gs.blocksPlaced}',
      'Kills ${gs.mobsKilled}   Deaths ${gs.deaths}',
    ];
    for (var i = 0; i < lines.length; i++) {
      Hud.text(canvas, lines[i], Offset(sx, sy + i * 22), size: 15, color: const Color.fromRGBO(230, 230, 230, 1));
    }

    // Slots: 3 rows of 9 + hotbar row
    s._slotRects.clear();
    const sl = 56.0;
    final gx = panel.left + 300;
    final gy = panel.top + 100;
    for (var i = 0; i < Inventory.size; i++) {
      final col = i % 9;
      final row = i ~/ 9;
      final r = row == 0
          ? Rect.fromLTWH(gx + col * sl, gy + 3 * sl + 16, sl - 4, sl - 4)
          : Rect.fromLTWH(gx + col * sl, gy + (row - 1) * sl, sl - 4, sl - 4);
      s._slotRects.add(r);
      canvas.drawRect(r, Paint()..color = const Color.fromRGBO(51, 51, 61, 1));
      if (row == 0) canvas.drawRect(r, Paint()..color = const Color.fromRGBO(128, 128, 140, 1)..style = PaintingStyle.stroke..strokeWidth = 1);
      final id = player.inventory.idAt(i);
      if (id != '') {
        Hud.drawItemIcon(canvas, r, id);
        final n = player.inventory.countAt(i);
        if (n > 1) Hud.text(canvas, '$n', Offset(r.left + 4, r.bottom - 5), size: 14);
        if (player.inventory.bonusAt(i) > 0) {
          canvas.drawRect(r, Paint()..color = Hud.rarityColor(player.inventory.bonusAt(i))..style = PaintingStyle.stroke..strokeWidth = 2);
        }
      }
    }
    Hud.text(canvas, 'Hotbar', Offset(gx, gy + 3 * sl + 10), size: 12, color: const Color.fromRGBO(153, 153, 153, 1));

    // Chest grid (replaces the recipe column)
    s._chestRects.clear();
    final chest = game.chest;
    if (chest != null) {
      final cx0 = panel.left + 820;
      final cy0 = panel.top + 100;
      Hud.text(canvas, 'Chest', Offset(cx0, cy0 - 8), size: 16);
      const cs = 48.0;
      for (var i = 0; i < Inventory.size; i++) {
        final r = Rect.fromLTWH(cx0 + (i % 6) * cs, cy0 + (i ~/ 6) * cs, cs - 4, cs - 4);
        s._chestRects.add(r);
        canvas.drawRect(r, Paint()..color = const Color.fromRGBO(61, 51, 41, 1));
        final id = chest.idAt(i);
        if (id != '') {
          Hud.drawItemIcon(canvas, r, id);
          final n = chest.countAt(i);
          if (n > 1) Hud.text(canvas, '$n', Offset(r.left + 3, r.bottom - 4), size: 13);
        }
      }
    }
    // Recipes
    s._recipeRects.clear();
    final recipesHidden = chest != null;
    final rx = panel.left + 820;
    final ry = panel.top + 90;
    if (!recipesHidden) Hud.text(canvas, 'Craft${game.station == '' ? '' : ' ($title)'}', Offset(rx, ry - 8), size: 16);
    final recipes = recipesHidden ? <Recipe>[] : Recipes.available(game.station);
    const rowH = 30.0;
    const visible = 16;
    // The rows plus a strip for the scroll bar, clear of them.
    final body = Rect.fromLTWH(rx, ry, 292, visible * rowH);
    s._recipeBody = body;
    final scroll = s._recipeScroll;
    scroll.begin(canvas, body, recipes.length * rowH);
    for (var i = 0; i < recipes.length; i++) {
      final r = recipes[i];
      final rect = Rect.fromLTWH(rx, ry + i * rowH, 280, rowH - 3);
      // Only the rows the box shows are drawn.
      if (rect.bottom < body.top + scroll.offset || rect.top > body.bottom + scroll.offset) continue;
      final ok = Recipes.canCraft(r, player.inventory);
      canvas.drawRect(rect, Paint()..color = ok ? const Color.fromRGBO(46, 71, 46, 1) : const Color.fromRGBO(46, 46, 51, 1));
      Hud.drawItemIcon(canvas, Rect.fromLTWH(rect.left + 2, rect.top + 1, 26, 26), r.result);
      Hud.text(canvas, '${Items.displayName(r.result)} x${r.count}', Offset(rect.left + 34, rect.top + 19), size: 14,
          color: ok ? Colors.white : const Color.fromRGBO(153, 153, 153, 1));
      s._recipeRects.add((rect, r));
    }
    scroll.end(canvas, body);
    if (recipes.length > visible) {
      final shown = ((scroll.offset + body.height) / rowH).floor().clamp(0, recipes.length);
      Hud.text(canvas, '${scroll.hasMore ? 'Scroll for more' : 'End of the list'} ($shown/${recipes.length})',
          Offset(rx, ry + visible * rowH + 14), size: 12, color: const Color.fromRGBO(153, 153, 153, 1));
    }

    // Hover tooltip
    final mp = s._mouse;
    var hover = '';
    for (var i = 0; i < s._slotRects.length; i++) {
      if (s._slotRects[i].contains(mp) && player.inventory.idAt(i) != '') {
        hover = _describe(player.inventory.idAt(i));
        final b = player.inventory.bonusAt(i);
        if (b > 0) hover = '${Hud.itemLabel(player.inventory.idAt(i), b)} — +$b damage';
      }
    }
    final r = s._recipeAt(mp);
    if (r != null) {
      final parts = [for (final e in r.ingredients.entries) '${Items.displayName(e.key)} x${e.value} (${player.inventory.countOf(e.key)})'];
      hover = '${_describe(r.result)}\nNeeds: ${parts.join(', ')}';
    }
    if (hover != '') {
      const w = 380.0;
      canvas.drawRect(Rect.fromLTWH(mp.dx + 14, mp.dy + 10, w, 52), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.9));
      Hud.text(canvas, hover, mp + const Offset(20, 28), size: 13, width: w - 12, shadow: false);
    }

    // Cursor stack
    final cur = s._cursor;
    if (cur != null) {
      final r = Rect.fromCenter(center: mp, width: 44, height: 44);
      Hud.drawItemIcon(canvas, r, cur.id);
      if (cur.count > 1) Hud.text(canvas, '${cur.count}', mp + const Offset(6, 20), size: 14);
    }
    canvas.restore();
    // Keep Blocks referenced for the icon shapes.
    assert(Blocks.count > 0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
