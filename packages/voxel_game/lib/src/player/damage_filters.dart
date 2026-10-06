import '../entities/target.dart';
import '../mobs/mob.dart';

/// A game's say on a hurt the player takes (`PlayerEntity.damageIn`): given
/// [damage] and the [amount] it comes to so far (its own, or what the filter
/// before made of it), returns what it comes to. Filters run in the order
/// they were added, before armour; 0 is a hurt that never lands (a dodge),
/// and one that never lands is not felt either. A hurt from within
/// (`Damage.internal`) is filtered too: a filter that should spare it asks.
typedef DamageInFilter = double Function(Damage damage, double amount);

/// A game's say on a blow the player deals a creature (`PlayerEntity.damageOut`):
/// given the [target] and the [amount] the blow comes to so far (its tool,
/// effects, boosts and critical roll counted), returns what it comes to.
typedef DamageOutFilter = double Function(Mob target, double amount);
