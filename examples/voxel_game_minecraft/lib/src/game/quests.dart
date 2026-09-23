import '../player/player.dart';
import 'sfx.dart';

/// A chain of small quests: kill / collect / craft / reach.
/// One active at a time; rewards XP and items.
class Quest {
  const Quest(this.id, this.title, this.text, this.kind, this.target, this.n, this.xp, this.items);
  final String id;
  final String title;
  final String text;
  final String kind;
  final List<String> target;
  final int n;
  final int xp;
  final Map<String, int> items;
}

/// Stage 24: one row of the journal's Quests tab.
typedef QuestEntry = ({String title, String text, int n, int xp, String state, int progress});

/// The journal's tab list (Godot's `JournalScreen.TABS` / `TAB_QUESTS`), kept
/// here so the game and its probe can name a tab without importing the UI.
class JournalTabs {
  JournalTabs._();
  static const List<String> names = ['Talents', 'Bestiary', 'Achievements', 'Waypoints', 'Quests'];
  static const int quests = 4;

  /// The chain in order — done ones greyed with a tick, the active one lit with
  /// its progress, the ones ahead dim. What the tab lists (the probe counts it).
  static List<QuestEntry> questEntries(QuestLog log) => [
        for (var i = 0; i < QuestLog.chain.length; i++)
          (
            title: QuestLog.chain[i].title,
            text: QuestLog.chain[i].text,
            n: QuestLog.chain[i].n,
            xp: QuestLog.chain[i].xp,
            state: i < log.index ? 'done' : (i == log.index ? 'active' : 'locked'),
            progress: i < log.index ? QuestLog.chain[i].n : (i == log.index ? log.progress : 0),
          ),
      ];
}

class QuestLog {
  static const List<Quest> chain = [
    Quest('wood', 'Gather wood', 'Punch or chop 8 logs', 'collect', ['oak_log', 'spruce_log'], 8, 20, {'apple': 2}),
    Quest('table', 'Set up a workbench', 'Craft a Crafting Table', 'craft', ['crafting_table'], 1, 20, {'torch': 4}),
    Quest('stone_pick', 'Stone age', 'Craft a Stone Pickaxe', 'craft', ['stone_pickaxe'], 1, 30, {'bread': 2}),
    Quest('sheep', 'Dinner time', 'Collect 3 raw meat', 'collect', ['raw_mutton', 'raw_beef', 'raw_pork', 'raw_chicken'], 3, 30, {'coal': 6}),
    Quest('night', 'Night watch', 'Slay 5 monsters', 'kill', ['zombie', 'skeleton', 'spider', 'slime', 'cave_slime', 'scorpion', 'snow_golem'], 5, 60, {'iron_ingot': 3, 'string': 3}),
    Quest('coal', 'Miner', 'Mine 10 coal', 'collect', ['coal'], 10, 40, {'lamp': 1}),
    Quest('iron', 'Iron will', 'Smelt 5 iron ingots', 'craft', ['iron_ingot'], 5, 60, {'magic_dust': 2}),
    Quest('level5', 'Adventurer', 'Reach level 5', 'level', [], 5, 80, {'health_potion': 2}),
    Quest('glider', 'Take to the skies', 'Craft or find a Hang Glider', 'have', ['glider'], 1, 80, {'gold_ingot': 2}),
    Quest('troll', 'Dungeon delver', 'Slay a Cave Troll', 'kill', ['troll'], 1, 200, {'diamond': 3, 'crystal_staff': 1}),
    Quest('diamond', 'Shine bright', 'Mine 3 diamonds', 'collect', ['diamond'], 3, 150, {'diamond_sword': 1}),
    Quest('level10', 'Hero of Dawnforge', 'Reach level 10', 'level', [], 10, 300, {'diamond_armor': 1}),
  ];

  int index = 0;
  int progress = 0;
  late Player player;

  Quest? get current => index < chain.length ? chain[index] : null;

  void _advance(int n) {
    final q = current;
    if (q == null) return;
    progress += n;
    if (progress >= q.n) {
      player.notify('Quest complete: ${q.title}!');
      Sfx.play('quest');
      player.gainXp(q.xp);
      for (final e in q.items.entries) {
        player.inventory.add(e.key, e.value);
      }
      index += 1;
      progress = 0;
      if (index < chain.length) player.notify('New quest: ${current!.title}');
      _checkHave();
    }
  }

  void _checkHave() {
    final q = current;
    if (q == null) return;
    if (q.kind == 'have') {
      for (final t in q.target) {
        if (player.inventory.countOf(t) >= q.n) {
          _advance(q.n);
          return;
        }
      }
    } else if (q.kind == 'level' && player.level >= q.n) {
      _advance(q.n);
    }
  }

  void onKill(String speciesId) {
    final q = current;
    if (q != null && q.kind == 'kill' && q.target.contains(speciesId)) _advance(1);
  }

  void onPickup(String itemId, int n) {
    final q = current;
    if (q == null) return;
    if (q.kind == 'collect' && q.target.contains(itemId)) {
      _advance(n);
    } else if (q.kind == 'have') {
      _checkHave();
    }
  }

  void onCraft(String itemId, int n) {
    final q = current;
    if (q == null) return;
    if (q.kind == 'craft' && q.target.contains(itemId)) {
      _advance(n);
    } else if (q.kind == 'have') {
      _checkHave();
    }
  }

  void onLevel(int level) => _checkHave();

  Map<String, Object> toJson() => {'index': index, 'progress': progress};

  void fromJson(Map<String, dynamic> d) {
    index = (d['index'] as num?)?.toInt() ?? 0;
    progress = (d['progress'] as num?)?.toInt() ?? 0;
  }
}
