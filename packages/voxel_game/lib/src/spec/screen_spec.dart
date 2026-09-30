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
/// screens: {'controls': ScreenSpec(controlsScreen, menu: 'Controls')},
/// ```
class ScreenSpec {
  /// A screen built by [build], listed in the game menu as [menu] when given.
  const ScreenSpec(this.build, {this.menu});

  /// Builds it.
  final ScreenBuilder build;

  /// The label of its button in the game menu (`PauseScreen`), or null for
  /// a screen only the game's code opens (a trade, from a creature). On a
  /// phone the menu is the one way to a screen a desktop opens with a key.
  final String? menu;
}
