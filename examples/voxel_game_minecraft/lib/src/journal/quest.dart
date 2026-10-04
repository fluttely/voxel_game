/// What a quest asks.
enum QuestGoal {
  /// Pick up [Quest.count] of its targets, all told (items).
  collect,

  /// Craft [Quest.count] of its targets, all told (items).
  craft,

  /// Kill [Quest.count] creatures of its targets (kinds, an elite as its own).
  kill,

  /// Reach level [Quest.count].
  level,

  /// Carry [Quest.count] of one of its targets (items).
  have,
}

/// One quest of the chain (`questChain`): what it asks, and what it gives.
class Quest {
  /// The quest [id], shown as [title] and [text]: [goal] [count] times over
  /// [targets], worth [xp] and [items].
  const Quest(
    this.id,
    this.title,
    this.text,
    this.goal,
    this.count, {
    this.targets = const [],
    required this.xp,
    required this.items,
  }) : assert(count > 0 && xp >= 0);

  /// Its key.
  final String id;

  /// What the journal and the HUD call it.
  final String title;

  /// What to do, in a line.
  final String text;

  /// What it asks.
  final QuestGoal goal;

  /// How many, or the level.
  final int count;

  /// The items or the kinds it counts; none for a level.
  final List<String> targets;

  /// The experience it gives.
  final int xp;

  /// The items it gives, by id.
  final Map<String, int> items;
}
