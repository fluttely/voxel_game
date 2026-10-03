import 'package:voxel_engine/content.dart' show ItemStack, Recipe;
import 'package:voxel_engine/core.dart';

import '../entities/target.dart';
import '../mobs/mob.dart';
import '../mobs/mob_spec.dart';
import '../spec/portal_spec.dart';
import '../ui/game_screen.dart';
import '../vehicles/vehicle.dart';

/// Something the player did, or that happened to them or around them, handed
/// to every `GameSystem` in the step (`GameSystem.onEvent`): what a quest
/// counts, an achievement waits for, a tutorial watches. The events are this
/// side's: on a client, its own player's (and the creatures it sees die).
/// A save loading raises none.
///
/// ```dart
/// @override
/// void onEvent(VoxelGame game, GameEvent event) {
///   if (event case MobKilled(:final mob, byPlayer: true)) kills[mob.spec.id] = (kills[mob.spec.id] ?? 0) + 1;
/// }
/// ```
sealed class GameEvent {
  const GameEvent();
}

/// The player broke [block] (by name) at [cell]; a blast's blocks raise none.
final class BlockBroken extends GameEvent {
  /// [block] broken at [cell].
  const BlockBroken(this.block, this.cell);

  /// The block's name.
  final String block;

  /// Where it was.
  final IVec3 cell;
}

/// The player placed [block] (by name) at [cell] (a tall block's foot).
final class BlockPlaced extends GameEvent {
  /// [block] placed at [cell].
  const BlockPlaced(this.block, this.cell);

  /// The block's name.
  final String block;

  /// Where it went.
  final IVec3 cell;
}

/// A creature died: of a blow, a shot, a fall, its own blast, or the host
/// saying so for a replica.
final class MobKilled extends GameEvent {
  /// [mob] died, [byPlayer] when the player dealt it the last hurt.
  const MobKilled(this.mob, {required this.byPlayer});

  /// The creature, dead.
  final Mob mob;

  /// Whether the player hurt it last (`Mob.lastHurtBy`): a kill of theirs.
  final bool byPlayer;
}

/// [count] of [item] went into the player's bag off the ground, from a line
/// or from code (`PlayerEntity.pickUpStack`); what did not fit is not counted.
final class ItemPickedUp extends GameEvent {
  /// [count] of [item] picked up.
  const ItemPickedUp(this.item, this.count);

  /// The item's id.
  final String item;

  /// How many went in.
  final int count;
}

/// The player crafted [recipe] once (`PlayerEntity.craft`).
final class ItemCrafted extends GameEvent {
  /// [recipe] crafted.
  const ItemCrafted(this.recipe);

  /// What was made, of what.
  final Recipe recipe;
}

/// The player ate one [item] (`PlayerEntity.eatHeld`).
final class FoodEaten extends GameEvent {
  /// [item] eaten.
  const FoodEaten(this.item);

  /// The food's id.
  final String item;
}

/// The player reached [level] (`PlayerEntity.gainXp`): one event a level, so
/// a gain of two levels raises two.
final class LevelGained extends GameEvent {
  /// [level] reached.
  const LevelGained(this.level);

  /// The level reached.
  final int level;
}

/// The player died, of [cause] (null for `PlayerEntity.kill` called with
/// none).
final class PlayerDied extends GameEvent {
  /// Died of [cause].
  const PlayerDied(this.cause);

  /// The blow that took the last health, or null.
  final Damage? cause;
}

/// The player left dimension [from] for [to] (`VoxelGame.travel`), [through]
/// a portal or not (a respawn's trip home, a game's own).
final class Travelled extends GameEvent {
  /// From [from] to [to], [through] a portal or not.
  const Travelled(this.from, this.to, {this.through});

  /// The dimension left, by id.
  final String from;

  /// The dimension gone to, by id.
  final String to;

  /// The portal gone through, or null.
  final PortalSpec? through;
}

/// The player got on [mount], their own tamed creature.
final class Mounted extends GameEvent {
  /// Got on [mount].
  const Mounted(this.mount);

  /// The creature ridden.
  final Mob mount;
}

/// The player got into [vehicle].
final class Boarded extends GameEvent {
  /// Got into [vehicle].
  const Boarded(this.vehicle);

  /// The vehicle.
  final Vehicle vehicle;
}

/// The player tamed a creature of [species]: here, or on the host for a
/// client.
final class Tamed extends GameEvent {
  /// A [species] tamed.
  const Tamed(this.species);

  /// What was tamed.
  final MobSpec species;
}

/// The player landed what bit their line: [stacks], one roll of
/// `FishingSpec.catches`, empty when nothing was on it.
final class Caught extends GameEvent {
  /// [stacks] landed.
  const Caught(this.stacks);

  /// What came out of the water (each also an [ItemPickedUp], or dropped
  /// when the bag was full).
  final List<ItemStack> stacks;
}

/// [screen] opened over the world (`VoxelGame.openScreen`; the death
/// screen is a [PlayerDied]).
final class ScreenOpened extends GameEvent {
  /// [screen] opened.
  const ScreenOpened(this.screen);

  /// The screen.
  final GameScreen screen;
}
