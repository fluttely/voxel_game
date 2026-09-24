import 'package:flutter/foundation.dart';

import 'settings.dart';
import 'sfx.dart';

class TutorialStep {
  const TutorialStep(this.id, this.title, this.hint);
  final String id;
  final String title;
  final String hint;
}

/// Stage 30: ten guided first steps on a new world, one card at the top of the
/// screen with the key to press; each step completes on the event the game
/// already raises (`event(id)` is called where the thing happens). Skippable
/// (the card's button, or F6). `Settings.tutorialDone` remembers it across
/// worlds; `--no-tutorial` keeps a probe quiet. Godot's autoload owns its
/// `CanvasLayer` card; here the state is a `ChangeNotifier` and the game view
/// draws `TutorialCard` from it.
class Tutorial extends ChangeNotifier {
  Tutorial._();
  static final Tutorial instance = Tutorial._();

  static const List<TutorialStep> steps = [
    TutorialStep('move', 'Walk', 'Press W A S D to walk around.'),
    TutorialStep('look', 'Look', 'Move the mouse to look around.'),
    TutorialStep('jump', 'Jump', 'Press Space to jump. Walk into a one-block step to hop up.'),
    TutorialStep('break', 'Break a block', 'Hold the left mouse button on a block until it breaks.'),
    TutorialStep('inventory', 'Open your bag', 'Press E to open the inventory and the crafting list.'),
    TutorialStep('craft', 'Craft a tool', 'Logs make planks, planks make sticks, planks + sticks make a pickaxe. Click a recipe.'),
    TutorialStep('place', 'Place a block', 'Pick a block on the hotbar (1-9) and press the right mouse button.'),
    TutorialStep('eat', 'Eat', 'Hold food and press H when the hunger bar drops.'),
    TutorialStep('sleep', 'Sleep', 'Craft a bed (3 planks + 3 wool) and use it at night, or survive until sunrise.'),
    TutorialStep('journal', 'Read the journal', 'Press J: talents, bestiary, achievements, waypoints and quests.'),
  ];

  bool active = false;
  int index = 0;
  final List<String> completed = [];

  /// The HUD notice when the chain ends (set by `Game`).
  void Function(String text)? notify;

  /// Unit tests turn the save and the sound off.
  bool persist = true;

  int get stepCount => steps.length;
  String get currentId => index < steps.length ? steps[index].id : '';
  TutorialStep? get current => active && index < steps.length ? steps[index] : null;

  /// Starts the chain unless it was finished on this machine before.
  void begin() {
    if (Settings.instance.tutorialDone) return;
    active = true;
    index = 0;
    completed.clear();
    notifyListeners();
  }

  /// Called where the game does the thing; only the event of the current step
  /// advances it.
  void event(String id) {
    if (!active || id != currentId) return;
    completed.add(id);
    index += 1;
    if (persist) Sfx.play('quest', -8.0);
    if (index >= steps.length) {
      _finish('Tutorial complete. Go explore!');
    } else {
      notifyListeners();
    }
  }

  /// Leaving the world (back to the title): the card goes, the chain is not
  /// marked done.
  void stop() {
    active = false;
    notifyListeners();
  }

  void skipAll() {
    if (active) _finish('Tutorial skipped.');
  }

  void _finish(String text) {
    active = false;
    Settings.instance.tutorialDone = true;
    if (persist) Settings.instance.save();
    notifyListeners();
    notify?.call(text);
  }
}
