import 'package:voxel_game/voxel_game.dart';

import 'class_system.dart';

/// What an ability does once it is paid for: [classes] is the player's.
typedef AbilityCast = void Function(VoxelGame game, ClassSystem classes);

/// One of a class's abilities (`PlayerClass.abilities`): its name, what it
/// costs and how long it takes to come back, and what it does ([cast]).
/// `ClassSystem` checks the [cooldown] and the costs, pays them, then casts.
class Ability {
  /// The ability [name], cast by [cast] every [cooldown] seconds for
  /// [stamina], [mana] (less the class's `Talent.manaCost`) and [arrows].
  const Ability(
    this.name, {
    required this.cooldown,
    required this.cast,
    this.stamina = 0.0,
    this.mana = 0.0,
    this.arrows = 0,
  }) : assert(cooldown > 0.0 && stamina >= 0.0 && mana >= 0.0 && arrows >= 0);

  /// What the HUD and the notices call it.
  final String name;

  /// Seconds before it can be cast again.
  final double cooldown;

  /// Stamina it costs.
  final double stamina;

  /// Mana it costs, before the talents.
  final double mana;

  /// Arrows it takes from the bag.
  final int arrows;

  /// What it does.
  final AbilityCast cast;
}
