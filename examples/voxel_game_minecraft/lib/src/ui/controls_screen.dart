import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

/// What every key does (F1, and Controls in the game menu): the keyboard and
/// mouse, a pad, and a phone.
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
    ],
    'Gamepad': [
      'Left stick  walk  ·  Right stick  look  ·  A  jump  ·  B  sneak  ·  Y  bag',
      'Right trigger  mine and hit  ·  Left trigger  place and use',
      'Bumpers  your powers  ·  X  dodge  ·  Touchpad  journal',
      'D-pad: up glide, right fly, down drop, left skip the tutorial  ·  Start  menu',
      'Back  the map: small, then big, then gone  ·  Home  these controls',
    ],
    'Phone': [
      'The stick at the left walks; drag anywhere else to look',
      'Tap to hit or use, hold to mine; the buttons at the right do the rest',
      'The map button shows the map small, then big, then hides it',
      'The menu button at the top has the journal, the map, the stats and these controls',
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
                          for (final MapEntry(key: way, value: lines) in sections.entries) ...[
                            const SizedBox(height: 10),
                            Text(way, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            for (final line in lines) Text(line),
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
