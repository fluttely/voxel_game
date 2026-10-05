import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import '../classes/class_system.dart';
import '../classes/talent.dart';
import '../waypoints/waypoints.dart';
import 'achievement_table.dart';
import 'achievements.dart';
import 'bestiary.dart';
import 'quest_chain.dart';
import 'quest_log.dart';

/// The journal (J, and Journal in the game menu), a tab each: the class's
/// talents, a point from each level to spend on one ([ClassSystem.learn]);
/// the creatures met and killed (`Bestiary`); the achievements; the
/// waypoints, a tap on one a trip there (`Waypoints`); and the quest chain,
/// the one at hand with how far it is. The world keeps going behind it, so
/// every tab follows what the game counts while it is open.
///
/// A pad and the keys work it through the focus (the kit's `ScreenFocus`):
/// it opens on its tab, left and right go from tab to tab and A opens one,
/// down walks the tab's rows (each takes the focus, so a long list scrolls
/// under it), and A on a talent's row learns it, as its button does.
class JournalScreen extends StatelessWidget {
  /// The journal of [game]'s player, open on the tab [initialTab].
  const JournalScreen(this.game, {super.key, this.initialTab = 0});

  /// A `ScreenBuilder` of this screen.
  static Widget builder(BuildContext context, VoxelGame game) => JournalScreen(game);

  /// A `ScreenBuilder` of this screen open on its Waypoints tab: what a
  /// waypoint's use opens.
  static Widget waypointsBuilder(BuildContext context, VoxelGame game) =>
      JournalScreen(game, initialTab: tabs.indexOf('Waypoints'));

  /// The tabs, in order.
  static const List<String> tabs = ['Talents', 'Creatures', 'Achievements', 'Waypoints', 'Quests'];

  /// The game whose journal it is.
  final VoxelGame game;

  /// The tab it opens on, an index of [tabs].
  final int initialTab;

  static const Color _gold = Color(0xFFFFE680);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 600),
            child: DefaultTabController(
              length: tabs.length,
              initialIndex: initialTab,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Journal', style: TextStyle(fontSize: 22)),
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.center,
                      tabs: [for (final (i, t) in tabs.indexed) i == initialTab ? _OpenTab(t) : Tab(text: t)],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(children: [_talents(), _bestiary(), _achievements(), _waypoints(), _quests()]),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: game.closeScreen, child: const Text('Back to the game')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _talents() {
    final c = ClassSystem.of(game);
    return HudSelector(
      frames: game.frames,
      select: () => (points: c.points, ranks: c.talents.map((t) => c.rank(t.id)).join(',')),
      builder: (context, s) => Column(
        children: [
          Text('${c.playerClass.name} talents', style: const TextStyle(fontSize: 18)),
          Text('Talent points: ${s.points}   (you get one each level)', style: const TextStyle(color: _gold)),
          Expanded(child: ListView(children: [for (final t in c.talents) _talent(c, t)])),
        ],
      ),
    );
  }

  Widget _talent(ClassSystem c, Talent t) {
    final rank = c.rank(t.id);
    final maxed = rank >= Talent.maxRank;
    final learn = maxed || c.points <= 0 ? null : () => c.learn(t.id);
    // The row learns too: it is where a pad's focus stops, once a row (the
    // button inside it is never the way up or down). Each row of the journal
    // is in a FocusFill: one with nothing to press still shows the focus.
    return FocusFill(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Color(0xFF000000 | t.color), radius: 14),
        title: Text('${t.name}  $rank/${Talent.maxRank}'),
        subtitle: Text(t.description),
        onTap: learn,
        trailing: FilledButton(onPressed: learn, child: Text(maxed ? 'Maxed' : 'Learn')),
      ),
    );
  }

  Widget _bestiary() {
    final b = Bestiary.of(game);
    return HudSelector(
      frames: game.frames,
      select: () => [for (final s in Bestiary.kinds) b.met(s.id) ? b.killsOf(s.id) : -1],
      equals: listEquals,
      builder: (context, _) => ListView(
        children: [
          for (final s in Bestiary.kinds)
            if (b.met(s.id))
              FocusFill(
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(backgroundColor: Color(0xFF000000 | s.rig.skinColor), radius: 12),
                  title: Text(s.boss ? '${s.name}  (boss)' : s.name),
                  subtitle: Text(creatureLine(s, b.killsOf(s.id))),
                ),
              )
            else
              FocusFill(
                child: const ListTile(
                  dense: true,
                  leading: CircleAvatar(backgroundColor: Color(0xFF4D4D4D), radius: 12),
                  title: Text('???'),
                  subtitle: Text('Not met yet'),
                ),
              ),
        ],
      ),
    );
  }

  /// What the bestiary says of a creature [s] met, killed [kills] times:
  /// its health, how hard it hits when it does, the experience it is worth.
  static String creatureLine(MobSpec s, int kills) {
    final hit = _hitOf(s);
    return [
      'Health ${s.hp.round()}',
      if (hit > 0.0) 'hits for ${hit.round()}',
      'XP ${s.xp}',
      'defeated $kills',
    ].join('   ');
  }

  // How hard [s] hits: its blow, else its shot; 0 for one that never does.
  static double _hitOf(MobSpec s) {
    for (final b in s.brain) {
      switch (b) {
        case MeleeAttack(:final damage):
          return damage;
        case RangedAttack(:final projectile):
          return projectile.damage;
        default:
      }
    }
    return 0.0;
  }

  Widget _achievements() {
    final a = Achievements.of(game);
    return HudSelector(
      frames: game.frames,
      select: () => a.unlocked.length,
      builder: (context, count) => Column(
        children: [
          Text('$count / ${achievementTable.length} unlocked', style: const TextStyle(color: _gold)),
          Expanded(
            child: ListView(
              children: [
                for (final row in achievementTable)
                  FocusFill(
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        a.has(row.id) ? Icons.star : Icons.star_border,
                        color: a.has(row.id) ? _gold : null,
                      ),
                      title: Text(row.name),
                      subtitle: Text(row.description),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _waypoints() {
    final w = Waypoints.of(game);
    return HudSelector(
      frames: game.frames,
      select: () => [for (final p in w.all) waypointLine(game, p)],
      equals: listEquals,
      builder: (context, lines) {
        final all = w.all;
        return Column(
          children: [
            Text(
              'Tap a waypoint to go there. It is free next to a waypoint, and costs '
              '${Waypoints.cost.round()} mana from anywhere else.',
              style: TextStyle(color: _gold),
            ),
            Expanded(
              child: all.isEmpty
                  ? const Center(
                      child: Text(
                        'No waypoints yet. Make one at a crafting table from 4 stone bricks and 2 magic dust, '
                        'then place it.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView(
                      children: [
                        for (var i = 0; i < all.length; i++)
                          FocusFill(
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.place, color: Color(0xFF4DF2FF)),
                              title: Text(lines[i]),
                              enabled: all[i].dimension == game.dimension,
                              onTap: () {
                                if (w.travel(game, all[i])) game.closeScreen();
                              },
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  /// How the journal lists the waypoint [w]: its label, its cell, and how
  /// far it is (`Waypoint 2   (10, 64, -3)   25 m away`), or the world it is
  /// in when that is not the player's.
  static String waypointLine(VoxelGame game, Waypoint w) {
    final c = w.cell;
    final where = w.dimension == game.dimension
        ? '${Waypoints.landingOf(w).distanceTo(game.player.position).round()} m away'
        : 'in the ${w.dimension}';
    return '${w.label}   (${c.x}, ${c.y}, ${c.z})   $where';
  }

  Widget _quests() {
    final log = QuestLog.of(game);
    return HudSelector(
      frames: game.frames,
      select: () => (done: log.index, progress: log.progressOf(game)),
      builder: (context, s) => Column(
        children: [
          Text('${s.done} / ${questChain.length} quests done', style: const TextStyle(color: _gold)),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < questChain.length; i++) _quest(i, s.done, s.progress),
                if (s.done >= questChain.length)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Every quest is done. You are the Hero of Dawnforge!', style: TextStyle(color: _gold)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quest(int i, int done, int progress) {
    final q = questChain[i];
    final finished = i < done;
    final active = i == done;
    final count = finished ? q.count : (active ? progress : 0);
    return FocusFill(
      child: ListTile(
        dense: true,
        enabled: finished || active,
        selected: active,
        leading: Icon(
          finished
              ? Icons.check
              : active
              ? Icons.play_arrow
              : Icons.lock_outline,
        ),
        title: Text(q.title),
        subtitle: Text('${q.text}   $count/${q.count}   ${q.xp} XP'),
        trailing: active ? SizedBox(width: 120, child: LinearProgressIndicator(value: progress / q.count)) : null,
      ),
    );
  }
}

// The tab the journal opens on, which takes the focus once laid out: a tab
// bar's tab has no autofocus, and its focus is the one around this.
class _OpenTab extends StatefulWidget {
  const _OpenTab(this.text);

  final String text;

  @override
  State<_OpenTab> createState() => _OpenTabState();
}

class _OpenTabState extends State<_OpenTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Focus.of(context).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => Tab(text: widget.text);
}
