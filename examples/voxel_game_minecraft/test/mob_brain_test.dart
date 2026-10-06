import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/spec/mob_table.dart';

/// The species table read as brains of the kit's behaviours: what each kind
/// does is a row, and the kit's selector runs it.
void main() {
  final byId = {for (final m in mobTable) m.id: m};
  List<Type> brain(String id) => [for (final b in byId[id]!.brain) b.runtimeType];
  List<Type> tamed(String id) => [for (final b in byId[id]!.tamedBrain) b.runtimeType];

  test('each kind of creature thinks with its own goals', () {
    expect(brain('sheep'), [FleeWhenHurt, Wander], reason: 'a farm animal runs when hurt and roams');
    expect(brain('wolf'), [MeleeAttack, Hunt, Wander], reason: 'a neutral one answers a hit');
    expect(byId['wolf']!.brain.whereType<Hunt>().single.whenProvoked, isTrue);
    expect(brain('zombie'), [MeleeAttack, Hunt, Wander]);
    expect(byId['zombie']!.brain.whereType<Hunt>().single.whenProvoked, isFalse);
    expect(brain('skeleton'), [RangedAttack, Hunt, Wander], reason: 'an archer shoots and never closes to strike');
    expect(brain('boomer'), [Explode, Hunt, Wander]);
    expect(brain('villager'), [Wander], reason: 'a trader never fights nor flees');
    expect(tamed('horse'), [MountWait]);
    expect(tamed('wolf'), [MeleeAttack, PetFight, Heel]);
  });

  test('every creature wild or tamed has something to do with its legs last', () {
    for (final m in mobTable) {
      expect(m.brain.last, isA<Wander>(), reason: m.id);
      if (m.tamedBrain.isNotEmpty) expect(m.tamedBrain.last, anyOf(isA<Heel>(), isA<MountWait>()), reason: m.id);
    }
  });
}
