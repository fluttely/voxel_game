import 'package:flutter/widgets.dart';

import 'world_option.dart';

/// A title screen, declared: `runVoxelGame(spec, menu: TitleSpec(...))`
/// opens on it instead of in a world. Its menu plays a world from the list
/// (made, renamed and deleted there), hosts one or joins a host, and sets the
/// player's settings; Quit, on a desktop, closes the app. The game menu's
/// Quit comes back to it.
class TitleSpec {
  /// A title reading [name].
  const TitleSpec({
    required this.name,
    this.tagline,
    this.modes = true,
    this.worldOptions = const [],
    this.multiplayer = true,
    this.port = 7777,
    this.credits = const [],
    this.background,
    this.music,
  }) : assert(name != '' && port > 0 && port < 65536);

  /// The game's name, large.
  final String name;

  /// A line under it, or none.
  final String? tagline;

  /// Whether a new world is made for survival or creative (`WorldMode`);
  /// when not, every world plays as the spec declares.
  final bool modes;

  /// The game's own choices a new world is made with, below the mode in the
  /// new-world form (see [WorldOption]).
  final List<WorldOption> worldOptions;

  /// Whether the menu hosts and joins (Multiplayer).
  final bool multiplayer;

  /// The port a hosted world listens on, and a joined address's when it
  /// names none.
  final int port;

  /// The credits, a line each, rolled up the screen; no Credits button when
  /// empty. An empty line is a gap.
  final List<String> credits;

  /// What the menu sits on; a dusk gradient when null.
  final WidgetBuilder? background;

  /// The track the menu plays, by name, one of the game's
  /// (`MusicSpec.tracks`); silence when null. It plays at the player's music
  /// volume, which the menu's Settings move at once, and stops before a
  /// world's music starts.
  final String? music;
}
