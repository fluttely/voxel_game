import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/species.dart';
import 'package:voxel_engine/core.dart';
import '../game/achievements.dart';
import '../game/game.dart';
import '../game/game_state.dart';
import '../game/quests.dart';
import '../game/sfx.dart';
import '../game/talents.dart';
import 'hud.dart';

/// The journal (J): talents to spend, the bestiary, achievements, waypoints and
/// the quest chain (stage 24), one tab each. Drawn by hand like the inventory screen; clicks are resolved
/// against the rects the painter recorded.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.game});
  final Game game;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  static const List<String> tabs = JournalTabs.names;

  final List<Rect> _tabRects = [];
  final List<(Rect, String)> _talentRects = [];
  final List<(Rect, IVec3)> _waypointRects = [];

  /// One scroll per tab: each list keeps where it was left.
  final List<PanelScroll> _scrolls = [for (var i = 0; i < tabs.length; i++) PanelScroll()];
  double _k = 1.0;
  Offset _origin = Offset.zero;

  Game get game => widget.game;
  int get tab => game.journalTab;
  PanelScroll get scroll => _scrolls[tab];
  late final PanelScrollInput _scrollInput = PanelScrollInput(() => scroll, () => _k);

  Offset _toPanel(Offset p) => Offset((p.dx - _origin.dx) / _k, (p.dy - _origin.dy) / _k);

  void _click(Offset mp) {
    for (var i = 0; i < _tabRects.length; i++) {
      if (_tabRects[i].contains(mp)) {
        game.journalTab = i;
        Sfx.play('click', -6.0);
        return;
      }
    }
    // A row was recorded where it was painted — inside the scrolled body.
    final cp = scroll.toContent(mp);
    if (tab == 0) {
      for (final pair in _talentRects) {
        if (pair.$1.contains(cp)) {
          if (game.player.learnTalent(pair.$2)) Sfx.play('levelup', -6.0);
          return;
        }
      }
    }
    if (tab == 3) {
      for (final pair in _waypointRects) {
        if (pair.$1.contains(cp)) {
          if (game.travelToWaypoint(pair.$2)) game.closeScreen();
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => setState(() {
        _scrollInput.down(e);
        // A finger may be starting a scroll: it acts when it lifts.
        if (e.kind != PointerDeviceKind.touch) _click(_toPanel(e.localPosition));
      }),
      onPointerMove: (e) => setState(() => _scrollInput.move(e)),
      onPointerUp: (e) => setState(() {
        if (e.kind == PointerDeviceKind.touch && !_scrollInput.dragged) _click(_toPanel(e.localPosition));
      }),
      onPointerSignal: (e) => setState(() => _scrollInput.signal(e)),
      onPointerPanZoomUpdate: (e) => setState(() => _scrollInput.panZoom(e)),
      child: CustomPaint(painter: _JournalPainter(this), size: Size.infinite),
    );
  }
}

const _dim = Color.fromRGBO(191, 191, 191, 1);
const _row = Color.fromRGBO(46, 46, 56, 1);
const _gold = Color.fromRGBO(255, 230, 128, 1);

class _JournalPainter extends CustomPainter {
  _JournalPainter(this.s) : super(repaint: s.game.frame);
  final _JournalScreenState s;

  static Paint _fill(Color c) => Paint()..color = c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _fill(const Color.fromRGBO(0, 0, 0, 0.55)));
    final k = ((size.width - 40) / 960).clamp(0.3, 1.0).toDouble().clamp(0.0, ((size.height - 40) / 600).clamp(0.3, 1.0));
    s._k = k;
    s._origin = Offset((size.width - 960 * k) / 2, (size.height - 600 * k) / 2);
    canvas.save();
    canvas.translate(s._origin.dx, s._origin.dy);
    canvas.scale(k);
    const panel = Rect.fromLTWH(0, 0, 960, 600);
    canvas.drawRect(panel, _fill(const Color.fromRGBO(31, 31, 38, 0.96)));
    canvas.drawRect(panel, Paint()
      ..color = const Color.fromRGBO(153, 153, 166, 1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    Hud.text(canvas, 'Journal', const Offset(20, 34), size: 24);
    Hud.text(canvas, 'Esc / J: close', const Offset(20, 56), size: 13, color: _dim);

    s._tabRects.clear();
    for (var i = 0; i < _JournalScreenState.tabs.length; i++) {
      final r = Rect.fromLTWH(190 + i * 150, 16, 142, 34);
      s._tabRects.add(r);
      canvas.drawRect(r, _fill(i == s.tab ? const Color.fromRGBO(64, 64, 82, 1) : const Color.fromRGBO(41, 41, 51, 1)));
      Hud.text(canvas, _JournalScreenState.tabs[i], r.topLeft + const Offset(12, 23),
          size: 16, color: i == s.tab ? Colors.white : _dim);
    }
    final body = const Rect.fromLTWH(20, 76, 920, 504);
    switch (s.tab) {
      case 0:
        _talents(canvas, body);
      case 1:
        _bestiary(canvas, body);
      case 2:
        _achievements(canvas, body);
      case 3:
        _waypoints(canvas, body);
      default:
        _quests(canvas, body);
    }
    canvas.restore();
  }

  void _talents(Canvas canvas, Rect body) {
    final player = s.game.player;
    s._talentRects.clear();
    Hud.text(canvas, 'Talent points: ${player.talentPoints}   (one per level from level 2)',
        body.topLeft + const Offset(0, 18), size: 16, color: _gold);
    final list = Rect.fromLTRB(body.left, body.top + 28, body.right, body.bottom);
    final talents = Talents.listFor(player.playerClass);
    s.scroll.begin(canvas, list, talents.length * 62.0);
    var y = list.top;
    for (final t in talents) {
      final rank = player.talentRank(t.id);
      final r = Rect.fromLTWH(body.left, y, body.width - 10, 56);
      final color = Color.fromRGBO((t.r * 255).round(), (t.g * 255).round(), (t.b * 255).round(), 1);
      canvas.drawRect(r, _fill(_row));
      canvas.drawRect(Rect.fromLTWH(r.left + 8, r.top + 8, 40, 40), _fill(color));
      Hud.text(canvas, '${t.name}  $rank/${Talents.maxRank}', r.topLeft + const Offset(60, 24), size: 18);
      Hud.text(canvas, t.description, r.topLeft + const Offset(60, 46), size: 13, color: _dim);
      for (var i = 0; i < Talents.maxRank; i++) {
        canvas.drawRect(Rect.fromLTWH(r.right - 240 + i * 22, r.top + 20, 16, 16),
            _fill(i < rank ? color : const Color.fromRGBO(77, 77, 89, 1)));
      }
      final can = player.talentPoints > 0 && rank < Talents.maxRank;
      final b = Rect.fromLTWH(r.right - 150, r.top + 12, 130, 32);
      canvas.drawRect(b, _fill(can ? const Color.fromRGBO(77, 140, 77, 1) : const Color.fromRGBO(64, 64, 71, 1)));
      Hud.text(canvas, rank < Talents.maxRank ? 'Learn' : 'Maxed', b.topLeft + const Offset(14, 22),
          size: 15, color: can ? Colors.white : _dim);
      s._talentRects.add((b, t.id));
      y += 62;
    }
    s.scroll.end(canvas, list);
  }

  void _bestiary(Canvas canvas, Rect body) {
    final st = GameState.instance;
    final defs = [for (final d in Species.defs.values) if (!d.trader) d];
    s.scroll.begin(canvas, body, 18 + ((defs.length + 1) ~/ 2) * 50.0);
    var i = 0;
    for (final d in defs) {
      final kills = st.kills[d.id] ?? 0;
      final seen = kills > 0 || st.seen.contains(d.id);
      final r = Rect.fromLTWH(body.left + (i % 2) * (body.width * 0.5), body.top + 18 + (i ~/ 2) * 50, body.width * 0.5 - 12, 44);
      canvas.drawRect(r, _fill(_row));
      final c = d.colors[0];
      canvas.drawRect(
          Rect.fromLTWH(r.left + 6, r.top + 6, 32, 32),
          _fill(seen
              ? Color.fromRGBO((c.x * 255).round(), (c.y * 255).round(), (c.z * 255).round(), 1)
              : const Color.fromRGBO(77, 77, 77, 1)));
      Hud.text(canvas, seen ? d.name : '???', r.topLeft + const Offset(46, 18), size: 16);
      var info = seen
          ? 'HP ${d.hp.toInt()}  DMG ${d.damage.toInt()}  XP ${d.xp}   kills $kills'
          : 'not met yet';
      if (seen && d.boss) info = 'BOSS  $info';
      Hud.text(canvas, info, r.topLeft + const Offset(46, 36), size: 12, color: _dim);
      i += 1;
    }
    s.scroll.end(canvas, body);
  }

  void _achievements(Canvas canvas, Rect body) {
    final ach = Achievements.instance;
    Hud.text(canvas, '${ach.count} / ${Achievements.defs.length} unlocked',
        body.topLeft + const Offset(0, 18), size: 16, color: _gold);
    s.scroll.begin(canvas, body, 30 + ((Achievements.defs.length + 1) ~/ 2) * 50.0);
    for (var i = 0; i < Achievements.defs.length; i++) {
      final d = Achievements.defs[i];
      final done = ach.unlocked.contains(d.id);
      final r = Rect.fromLTWH(body.left + (i % 2) * (body.width * 0.5), body.top + 30 + (i ~/ 2) * 50, body.width * 0.5 - 12, 44);
      canvas.drawRect(r, _fill(done ? const Color.fromRGBO(51, 71, 51, 1) : _row));
      Hud.text(canvas, '${done ? '*' : 'o'} ${d.name}', r.topLeft + const Offset(12, 18),
          size: 16, color: done ? _gold : Colors.white);
      Hud.text(canvas, d.description, r.topLeft + const Offset(12, 36), size: 12, color: _dim);
    }
    s.scroll.end(canvas, body);
  }

  void _waypoints(Canvas canvas, Rect body) {
    final game = s.game;
    s._waypointRects.clear();
    Hud.text(canvas, 'Click a waypoint to travel there (needs one within 6 blocks, or 10 mana from anywhere)',
        body.topLeft + const Offset(0, 18), size: 14, color: _dim);
    var y = body.top + 36;
    final entries = game.waypointList();
    if (entries.isEmpty) {
      Hud.text(canvas, 'No waypoints yet. Craft one: 4 stone bricks + 2 magic dust.',
          Offset(body.left, y + 20), size: 15, color: _dim);
    }
    // Stage 33: more than ten (the playground's world tour) run in two columns.
    final cols = entries.length > 10 ? 2 : 1;
    final perCol = (entries.length / cols).ceil();
    final colW = (body.width - 10.0 - 12.0 * (cols - 1)) / cols;
    s.scroll.begin(canvas, body, 36 + perCol * 46.0);
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final r = Rect.fromLTWH(body.left + (i ~/ perCol) * (colW + 12.0), y + (i % perCol) * 46.0, colW, 40);
      canvas.drawRect(r, _fill(_row));
      final dist = (e.key.toVector3() - game.player.position).length;
      Hud.text(canvas, '${e.value}   (${e.key.x}, ${e.key.y}, ${e.key.z})   ${dist.round()} m away',
          r.topLeft + const Offset(12, 26), size: 16);
      s._waypointRects.add((r, e.key));
    }
    s.scroll.end(canvas, body);
  }

  /// Stage 24: the quest chain in order.
  void _quests(Canvas canvas, Rect body) {
    final game = s.game;
    final entries = JournalTabs.questEntries(game.quests);
    final done = game.quests.index;
    Hud.text(canvas, '${done.clamp(0, entries.length)} / ${entries.length} quests done',
        body.topLeft + const Offset(0, 18), size: 16, color: _gold);
    var y = body.top + 30;
    const rowH = 40.0;
    s.scroll.begin(canvas, body, 30 + entries.length * rowH + 40);
    for (final e in entries) {
      final r = Rect.fromLTWH(body.left, y, body.width - 10, rowH - 4);
      final active = e.state == 'active';
      final finished = e.state == 'done';
      canvas.drawRect(r, _fill(active ? const Color.fromRGBO(71, 82, 51, 1) : const Color.fromRGBO(38, 38, 46, 1)));
      if (active) {
        canvas.drawRect(r, Paint()
          ..color = _gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
      final titleCol = finished
          ? const Color.fromRGBO(128, 128, 140, 1)
          : (active ? const Color.fromRGBO(255, 242, 179, 1) : const Color.fromRGBO(179, 179, 191, 1));
      final prefix = finished ? '✓ ' : (active ? '▶ ' : '   ');
      Hud.text(canvas, '$prefix${e.title}', r.topLeft + const Offset(12, 24), size: 16, color: titleCol);
      Hud.text(canvas, '${e.text}   ${e.progress}/${e.n}   ${e.xp} XP', r.topLeft + const Offset(300, 24),
          size: 13,
          color: finished
              ? const Color.fromRGBO(115, 115, 128, 1)
              : (active ? Colors.white : const Color.fromRGBO(153, 153, 166, 1)));
      if (active) {
        final bar = Rect.fromLTWH(r.right - 160, r.top + 12, 140, 12);
        canvas.drawRect(bar, _fill(const Color.fromRGBO(0, 0, 0, 0.6)));
        canvas.drawRect(Rect.fromLTWH(bar.left, bar.top, bar.width * (e.progress / e.n).clamp(0.0, 1.0), bar.height),
            _fill(const Color.fromRGBO(102, 217, 102, 1)));
      }
      y += rowH;
    }
    if (done >= entries.length) {
      Hud.text(canvas, 'Every quest is done. You are the Hero of Dawnforge!', Offset(body.left, y + 20),
          size: 15, color: _gold);
    }
    s.scroll.end(canvas, body);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
