import 'package:voxel_game_minecraft/src/core/species.dart';
import 'package:voxel_game_minecraft/src/entities/mob.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart' show BehaviorSlot;

/// VK5.5: the species table read as brains of goals on the kit's selector.
void main() {
  List<Type> brain(String id, {bool tamed = false}) => [for (final g in brainOf(Species.def(id), tamed: tamed)) g.runtimeType];

  test('each kind of creature thinks with its own goals', () {
    expect(brain('sheep'), [Flee, Roam], reason: 'a passive animal runs when hurt and roams');
    expect(brain('wolf'), [Flee, Strike, Chase, Roam], reason: 'a neutral one also answers a hit');
    expect(brain('zombie'), [Strike, Chase, Roam]);
    expect(brain('skeleton'), [Kite, Roam], reason: 'an archer keeps its distance and never closes to strike');
    expect(brain('boomer'), [Fuse, Chase, Roam]);
    expect(brain('villager'), [Roam], reason: 'a trader never fights nor flees');
    expect(brain('horse', tamed: true), [MountWait]);
    expect(brain('wolf', tamed: true), [PetFight, Heel]);
  });

  test('every brain is asked in priority order and always has something to do', () {
    for (final sp in Species.defs.values) {
      for (final tamed in [false, true]) {
        final goals = brainOf(sp, tamed: tamed);
        final priorities = [for (final g in goals) g.priority];
        expect(priorities, List<int>.of(priorities)..sort(), reason: '${sp.id} tamed=$tamed');
        expect(goals.last.slots, contains(BehaviorSlot.move), reason: '${sp.id}: the last goal holds the legs');
        expect(goals.last.priority, 90, reason: '${sp.id}: and is the fallback');
      }
    }
  });

  test('a creature without a species thinks nothing and reads idle', () {
    expect(Mob().state, MobState.idle);
  });
}
