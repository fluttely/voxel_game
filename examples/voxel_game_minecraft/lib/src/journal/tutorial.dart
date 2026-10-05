import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

import '../playground/playground.dart';
import 'game_stats.dart';
import 'tutorial_step.dart';
import 'tutorial_steps.dart';

/// The guided first steps of a new world ([tutorialSteps]), a card each at
/// the top of the screen (`TutorialCard`): only what finishes the step at
/// hand moves it on, with a chime, and the last one ends it. The card's
/// button and the `skip_tutorial` action (F6) end it at once. It is shown
/// once per machine: ended or skipped, it is marked [doneKey] in the
/// player's settings (`GameSettings.game`), and every world after starts it
/// ended, as a playground always does.
///
/// For the steps that are a state, it measures what the player did since
/// the step began: [walked], [turned] and [sunRose].
///
/// Where it is is saved with the world (under `tutorial`).
class Tutorial extends SavedSystem {
  /// The key of where it is in the save.
  static const String key = 'tutorial';

  /// The action that skips it.
  static const String skipAction = 'skip_tutorial';

  /// The key of the player's settings (`GameSettings.game`) true once this
  /// machine has seen it end.
  static const String doneKey = 'tutorialDone';

  /// Whether this machine has seen it end ([doneKey]): not before it has.
  static bool doneOn(VoxelGame game) => switch (game.settings.value.game[doneKey]) {
    null => false,
    final bool done => done,
    final other => throw ArgumentError.value(other, 'settings.game[$doneKey]', 'a bool'),
  };

  /// The tutorial of [game], started or ended by the player's settings the
  /// first time it is asked: what the HUD's card reads, which may draw before
  /// the game's first step.
  static Tutorial of(VoxelGame game) => game.system<Tutorial>().._begin(game);

  VoxelGame? _game;

  /// The steps done: [tutorialSteps]' length once it has ended.
  int step = 0;

  /// Metres walked on the ground since the step began.
  double walked = 0.0;

  /// Radians the view turned since the step began, yaw and pitch told
  /// together.
  double turned = 0.0;

  /// Whether the sun came up in the last step of the game.
  bool sunRose = false;

  Vector3? _at;
  double _yaw = 0.0, _pitch = 0.0, _timeOfDay = 0.0;

  /// The step at hand, or null once it has ended.
  TutorialStep? get current => step < tutorialSteps.length ? tutorialSteps[step] : null;

  /// Ends it now, told so; nothing once it has ended.
  void skip(VoxelGame game) {
    if (current == null) return;
    step = tutorialSteps.length;
    game.notify('Tutorial skipped.');
    _markDone(game);
  }

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    _begin(game);
    final on = current?.on;
    if (on != null && on(game, event)) _next(game);
  }

  @override
  void tick(VoxelGame game, double dt) {
    _begin(game);
    final p = game.player;
    final at = Vector3(p.position.x, 0.0, p.position.z);
    final last = _at;
    final stride = last == null ? 0.0 : at.distanceTo(last);
    if (p.onFloor && !p.isDead && stride <= GameStats.longestStride) walked += stride;
    _at = at;
    turned += (p.yaw - _yaw).abs() + (p.pitch - _pitch).abs();
    _yaw = p.yaw;
    _pitch = p.pitch;
    sunRose = _timeOfDay < 0.25 && game.timeOfDay >= 0.25;
    _timeOfDay = game.timeOfDay;
    if (current == null) return;
    if (game.actions.justPressed(skipAction)) return skip(game);
    final when = current!.when;
    if (when != null && game.gameplay && game.screen.value == null && when(game, this)) _next(game);
  }

  void _next(VoxelGame game) {
    step += 1;
    walked = 0.0;
    turned = 0.0;
    game.playSound('quest', volumeDb: -8.0);
    if (current != null) return;
    game.notify('Tutorial complete. Go explore!');
    _markDone(game);
  }

  // Kept by the player's settings, which the game widget writes to its file.
  void _markDone(VoxelGame game) {
    final s = game.settings.value;
    game.applySettings(s.copyWith(game: {...s.game, doneKey: true}));
  }

  // The settings' say, once: a machine that has seen it end starts it ended.
  void _begin(VoxelGame game) {
    if (_game != null) return;
    _game = game;
    final p = game.player;
    _yaw = p.yaw;
    _pitch = p.pitch;
    _timeOfDay = game.timeOfDay;
    // A playground has no tutorial.
    step = Playground.isOn(game) || doneOn(game) ? tutorialSteps.length : 0;
  }

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {'step': step};

  @override
  void restore(VoxelGame game, Object? saved) {
    _begin(game);
    final at = (saved! as Map<String, Object?>)['step']! as int;
    if (at < 0 || at > tutorialSteps.length) throw FormatException('no tutorial step $at');
    // A world saved halfway through goes on where it was, unless this machine
    // has seen the tutorial end since.
    if (!doneOn(game)) step = at;
  }
}
