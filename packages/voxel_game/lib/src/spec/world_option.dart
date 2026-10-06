/// A choice of the game's own that a new world is made with (a class, a
/// playground), offered by the new-world form (`TitleSpec.worldOptions`),
/// kept in the world's `world.json` (`WorldInfo.options`) and read by the
/// game's systems through `VoxelGame.options`; the player it makes, by
/// `VoxelGameSpec.playerFor`. One a player picks for themself as well (a
/// class) is offered by the join form too ([join]).
///
/// ```dart
/// WorldOption('class', label: 'Class', choices: {'warrior': 'Warrior', 'mage': 'Mage'})
/// ```
class WorldOption {
  /// The option [id], shown as [label], one of [choices].
  const WorldOption(this.id, {required this.label, required this.choices, this.join = false});

  /// Its key in `WorldInfo.options`.
  final String id;

  /// What the form calls it.
  final String label;

  /// Each value kept, to what the form shows for it, in the form's order;
  /// the first is chosen until the player picks another.
  final Map<String, String> choices;

  /// Whether the join form offers it too: a joined game plays with the
  /// choices made there (`VoxelGame.options`).
  final bool join;

  /// The value chosen until the player picks another.
  String get first => choices.keys.first;

  /// Throws for an option with no id or no choices, and for two options of
  /// one id: what a form offering [options] checks as it is built.
  static void check(List<WorldOption> options) {
    final ids = <String>{};
    for (final o in options) {
      if (o.id.isEmpty) throw ArgumentError.value(o.label, 'options', 'an option needs an id');
      if (o.choices.isEmpty) throw ArgumentError.value(o.id, 'options', 'an option needs a choice');
      if (!ids.add(o.id)) throw ArgumentError.value(o.id, 'options', 'two options of one id');
    }
  }
}
