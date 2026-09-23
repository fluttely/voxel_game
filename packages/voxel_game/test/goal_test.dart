import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

/// Any creature of a game's own: the selector never asks what it is.
class _Cat {
  double hunger = 0.0;
  bool mouse = false;
  final List<String> log = [];
}

class _Nap extends Goal<_Cat, String> {
  const _Nap() : super(priority: 90);

  @override
  bool canStart(_Cat mob, String game) => true;

  @override
  void tick(_Cat mob, String game, double dt) => mob.log.add('nap');

  @override
  void stop(_Cat mob, String game) => mob.log.add('wake');
}

class _Pounce extends Goal<_Cat, String> {
  const _Pounce() : super(priority: 10);

  @override
  Set<BehaviorSlot> get slots => const {BehaviorSlot.move, BehaviorSlot.attack};

  @override
  bool canStart(_Cat mob, String game) => mob.mouse;

  @override
  void tick(_Cat mob, String game, double dt) => mob.log.add('pounce in $game');
}

class _Purr extends Goal<_Cat, String> {
  const _Purr() : super(priority: 95);

  @override
  Set<BehaviorSlot> get slots => const {BehaviorSlot.look};

  @override
  bool canStart(_Cat mob, String game) => mob.hunger < 1.0;

  @override
  void tick(_Cat mob, String game, double dt) => mob.log.add('purr');
}

void main() {
  test('a selector runs any agent\'s goals by slot and priority', () {
    final cat = _Cat();
    final brain = GoalSelector<_Cat, String>(const [_Pounce(), _Nap(), _Purr()]);

    brain
      ..think(cat, 'the kitchen')
      ..tick(cat, 'the kitchen', 0.1);
    expect(cat.log, ['nap', 'purr'], reason: 'goals on separate slots run side by side');
    expect(brain.holding(BehaviorSlot.move), isA<_Nap>());

    cat
      ..log.clear()
      ..mouse = true;
    brain
      ..think(cat, 'the kitchen')
      ..tick(cat, 'the kitchen', 0.1);
    expect(cat.log, ['wake', 'purr', 'pounce in the kitchen'], reason: 'the outranking goal takes the shared slot and stops the other');

    cat
      ..log.clear()
      ..mouse = false
      ..hunger = 2.0;
    brain
      ..think(cat, 'the kitchen')
      ..tick(cat, 'the kitchen', 0.1);
    expect(cat.log, ['nap'], reason: 'what cannot continue stops, and what may starts again');

    cat.log.clear();
    brain.stopAll(cat, 'the kitchen');
    expect(cat.log, ['wake']);
    expect(brain.running, isEmpty);
  });
}
