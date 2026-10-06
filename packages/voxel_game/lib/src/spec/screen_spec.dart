import 'package:flutter/widgets.dart';

import '../core/voxel_game.dart';

/// Builds a screen of a game's own over the running game. It is built when
/// the screen opens, not every frame: a piece that shows the game's state
/// watches it through a `HudSelector`. It closes itself with
/// `VoxelGame.closeScreen`, and a press of pause closes it too.
typedef ScreenBuilder = Widget Function(BuildContext context, VoxelGame game);

/// A screen of a game's own (a journal, a trade, the controls), opened as a
/// `DeclaredScreen` of its key in `VoxelGameSpec.screens`.
///
/// ```dart
/// screens: {'controls': ScreenSpec(controlsScreen, menu: 'Controls', action: 'controls')},
/// ```
class ScreenSpec {
  /// A screen built by [build], listed in the game menu as [menu] when given
  /// (in the games [listed] says, when given) and opened by [action] when
  /// given.
  const ScreenSpec(this.build, {this.menu, this.action, this.listed})
    : assert(listed == null || menu != null, 'only a screen in the menu is listed');

  /// Builds it.
  final ScreenBuilder build;

  /// The label of its button in the game menu (`PauseScreen`), or null for
  /// a screen only the game's code opens (a trade, from a creature). On a
  /// phone the menu is the one way to a screen a desktop opens with a key.
  final String? menu;

  /// Whether the game menu lists it in a game: a playground's controls in a
  /// playground only, say. Null lists it in every game.
  final bool Function(VoxelGame game)? listed;

  /// Whether the game menu of [game] lists it: it has a [menu] label, and
  /// [listed] says so when given.
  bool listedIn(VoxelGame game) => menu != null && (listed?.call(game) ?? true);

  /// The id of one of the game's own actions (`VoxelGameSpec.actions`) that
  /// opens it while the player plays and closes it again, as the bag's key
  /// opens and closes the bag; null for none.
  final String? action;
}
