import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

/// What every key does (F1, and Controls in the game menu): the keyboard and
/// mouse, a pad, and a phone. Each way is a stop of the focus, filled when
/// it holds it, so a pad and the arrows walk them and the text scrolls under
/// them; it opens on the first.
class ControlsScreen extends StatelessWidget {
  /// The controls, over [game].
  const ControlsScreen(this.game, {super.key});

  /// A `ScreenBuilder` of this screen.
  static Widget builder(BuildContext context, VoxelGame game) => ControlsScreen(game);

  /// The game it closes back to.
  final VoxelGame game;

  /// Each way to play, and what its keys do, a line each.
  static const Map<String, List<String>> sections = {
    'Keyboard and mouse': [
      'W A S D  walk  ·  Space  jump  ·  Shift  run  ·  Ctrl  sneak',
      'Left click  mine and hit  ·  Right click  place, use, eat, wear',
      'E  bag  ·  Q  drop  ·  V  first or third person  ·  Esc  menu',
      'R and F  your class\'s two powers  ·  Alt  dodge  ·  J  journal',
      'G  glide, with a glider in the bag  ·  F5  fly, in a Creative world',
      'M  the map: small in the corner, then big, then gone',
      'F1  these controls  ·  F6  skip the tutorial',
      'On a menu: the arrows move  ·  Enter or Space  press  ·  Esc  go back',
      'In a playground: F7  the weather  ·  F8  the time of day  ·  F9  rebuild the exhibit you stand in',
    ],
    'Gamepad': [
      'Left stick  walk  ·  Right stick  look  ·  A  jump  ·  B  sneak  ·  Y  bag',
      'Right trigger  mine and hit  ·  Left trigger  place and use',
      'Bumpers  your powers  ·  X  dodge  ·  Touchpad  journal',
      'D-pad: up glide, right fly, down drop, left the next hotbar slot  ·  Start  menu',
      'Back  the map: small, then big, then gone  ·  Home  these controls',
      'In a playground, Playground in the menu changes the weather and the time and rebuilds an exhibit',
      'Tutorial in the menu skips the tutorial',
      'On a menu: the d-pad or the left stick moves  ·  A  press  ·  X  take half in the bag  ·  B  go back',
    ],
    'Phone': [
      'The stick at the left walks; drag anywhere else to look',
      'Tap to hit or use, hold to mine; the buttons at the right do the rest',
      'The map button shows the map small, then big, then hides it',
      'The menu button at the top has the journal, the map, the stats and these controls',
      'In a playground it has Playground too: the weather, the time, and a rebuild of the exhibit you stand in',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Controls', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, MapEntry(key: way, value: lines)) in sections.entries.indexed) ...[
                            const SizedBox(height: 10),
                            _Section(way, lines, autofocus: i == 0),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: game.closeScreen, child: const Text('Back to the game')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// A way to play and its lines: a stop of the focus with nothing to press,
// filled while it holds it.
class _Section extends StatelessWidget {
  const _Section(this.way, this.lines, {required this.autofocus});

  final String way;
  final List<String> lines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: autofocus,
    child: Builder(
      builder: (context) => ColoredBox(
        color: Focus.of(context).hasFocus ? ScreenFocus.fill : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(way, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            for (final line in lines) Text(line),
          ],
        ),
      ),
    ),
  );
}
