import 'package:voxel_game/voxel_game.dart';

import 'ability.dart';
import 'talent.dart';

/// A class a world's player plays (`WorldInfo.options['class']`): its
/// numbers, its colours, its weapon and its abilities, by action id
/// (`'ability'` on R, `'ability2'` on F). Its player is the game's through
/// `PlayerSpec.copyWith` (`classPlayer`); the rest is `ClassSystem`'s.
class PlayerClass {
  /// The class [name], with [hp] health, [stamina] and [mana] at level 0,
  /// drawn as [rig], [weapon] to start with and [kit] beside
  /// it, every blow times [damage], its [abilities] and its [signature]
  /// talent.
  const PlayerClass(
    this.name, {
    required this.hp,
    required this.stamina,
    required this.mana,
    required this.rig,
    required this.weapon,
    required this.damage,
    required this.abilities,
    required this.signature,
    this.kit = const {},
  });

  /// Stamina and mana each level adds.
  static const double perLevel = 5.0;

  /// What the title and the HUD call it.
  final String name;

  /// Health at level 0.
  final double hp;

  /// Stamina at level 0.
  final double stamina;

  /// Mana at level 0.
  final double mana;

  /// How it looks: its shirt is how every side tells the class.
  final Rig rig;

  /// The weapon it starts with.
  final String weapon;

  /// What it starts with beside the [weapon] and the game's own start: item
  /// id to count.
  final Map<String, int> kit;

  /// What every blow of its is multiplied by.
  final double damage;

  /// Its abilities, by the action id that casts each.
  final Map<String, Ability> abilities;

  /// Its own talent, after the six every class has.
  final Talent signature;
}
