import 'package:voxel_game/voxel_game.dart';

import 'tutorial.dart';

/// Whether [event] finishes a step of the tutorial in [game].
typedef TutorialEvent = bool Function(VoxelGame game, GameEvent event);

/// Whether what the player did in [game] since the step began (what
/// [tutorial] measured) finishes it; asked every step of play.
typedef TutorialState = bool Function(VoxelGame game, Tutorial tutorial);

/// One of the tutorial's first steps (`tutorialSteps`): its card, and what
/// finishes it, an event ([on]), a state ([when]), or either.
class TutorialStep {
  /// The step [id], its card [title] and [hint], finished [on] an event or
  /// [when] a state holds.
  const TutorialStep(this.id, this.title, this.hint, {this.on, this.when})
    : assert(on != null || when != null, 'a step finishes on something');

  /// Its key.
  final String id;

  /// The card's title.
  final String title;

  /// What to press, in a line.
  final String hint;

  /// The event that finishes it, or null.
  final TutorialEvent? on;

  /// The state that finishes it, or null.
  final TutorialState? when;
}
