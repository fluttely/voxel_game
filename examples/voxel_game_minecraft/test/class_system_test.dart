import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/classes/class_system.dart';
import 'package:voxel_game_minecraft/src/classes/class_table.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/spec/game_title.dart';

/// A game of [cls], its player the class's, as the title starts one.
Future<VoxelGame> _start(String cls, {SavedWorld? save}) async {
  final options = {'class': cls};
  final game = await VoxelGame.startHeadless(
    gameSpec.copyWith(player: gameSpec.playerWith(options)),
    options: options,
    save: save,
  );
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
  _run(game, 0.1);
  return game;
}

void _run(VoxelGame game, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.step(1 / 60);
  }
}

/// A creature of [id] [metres] in front of the player, on its feet.
Mob _ahead(VoxelGame game, String id, double metres) {
  final p = game.player;
  return game.spawnMob(id, p.position + p.flatForward * metres + Vector3(0.0, 0.5, 0.0));
}

void main() {
  test('each class is a player of its own: health, look, weapon and kit; its bars start full', () async {
    for (final MapEntry(key: id, value: cls) in playerClasses.entries) {
      final game = await _start(id);
      final p = game.player;
      final classes = ClassSystem.of(game);
      expect(p.spec.hp, cls.hp, reason: id);
      expect(p.hp, cls.hp);
      expect(p.spec.rig, same(cls.rig));
      expect(p.inventory.countOf(cls.weapon), 1);
      for (final MapEntry(key: item, value: count) in cls.kit.entries) {
        expect(p.inventory.countOf(item), count, reason: '$id starts with $item');
      }
      expect(p.inventory.countOf('torch'), 8, reason: 'beside the game\'s own start');
      expect(classes.playerClass, same(cls));
      expect((classes.stamina, classes.mana), (cls.stamina, cls.mana));
      expect(p.damageMultiplier, closeTo(cls.damage, 1e-9));
      game.dispose();
    }
    expect(classOption.choices.keys, playerClasses.keys, reason: 'the title offers every class, in order');
    expect(classOption.join, isTrue, reason: 'a player joining picks its own');
    expect(() => classPlayer(gameSpec.player, const {}), throwsArgumentError);
  });

  test('a sprint spends stamina and rest brings it back; spent, the player cannot sprint', () async {
    final game = await _start('warrior');
    final p = game.player;
    final classes = ClassSystem.of(game);
    game.input
      ..hold(VoxelAction.moveForward, true)
      ..hold(VoxelAction.sprint, true);
    _run(game, 1.0);
    expect(p.sprinting, isTrue);
    expect(classes.stamina, closeTo(100.0 - ClassSystem.sprintCost, 0.2));
    classes.stamina = 0.5;
    _run(game, 0.1);
    expect(p.sprinting, isFalse, reason: 'nothing left to run on');
    game.input.hold(VoxelAction.sprint, false);
    _run(game, 1.0);
    expect(classes.stamina, closeTo(0.5 + ClassSystem.staminaBack, 0.4));
    game.dispose();
  });

  test('an ability is paid for and cast, then waits; short of its cost it says so and spends nothing', () async {
    final game = await _start('warrior');
    final classes = ClassSystem.of(game);
    final cow = _ahead(game, 'cow', 2.0);
    final hp = cow.hp;
    game.actions.tap('ability');
    _run(game, 0.05);
    expect(cow.hp, lessThan(hp), reason: 'the whirlwind reached it');
    expect(classes.stamina, closeTo(100.0 - 25.0, 0.5));
    expect(classes.cooldownOf('ability'), closeTo(8.0, 0.1));
    game.actions.tap('ability');
    _run(game, 0.05);
    expect(game.notices.feed.map((n) => n.text), contains('Whirlwind ready in 8s'));
    expect(classes.stamina, greaterThan(100.0 - 25.0), reason: 'nothing spent');

    final mana = classes.mana = 5.0;
    game.actions.tap('ability2');
    _run(game, 0.02);
    expect(game.notices.feed.map((n) => n.text), contains('Not enough mana'));
    expect(classes.mana, closeTo(mana, 0.1));
    expect(classes.cooldownOf('ability2'), 0.0);
    game.dispose();
  });

  test('the shield bash stuns what is ahead; the frost nova slows; the smoke bomb hides the player', () async {
    final warrior = await _start('warrior');
    final ahead = _ahead(warrior, 'cow', 2.0);
    final behind = _ahead(warrior, 'cow', -2.0);
    warrior.actions.tap('ability2');
    _run(warrior, 0.05);
    expect(ahead.hp, lessThan(ahead.maxHp));
    expect(behind.hp, behind.maxHp, reason: 'a bash only reaches what is ahead');
    expect(ClassSystem.of(warrior).mana, closeTo(20.0 - 10.0, 0.2));
    warrior.dispose();

    final mage = await _start('mage');
    final near = _ahead(mage, 'cow', 3.0);
    mage.actions.tap('ability2');
    _run(mage, 0.05);
    expect(near.pace, 0.5, reason: 'frozen to half its pace');
    expect(near.hp, lessThan(near.maxHp));
    expect(ClassSystem.of(mage).mana, closeTo(100.0 - 25.0, 0.2));
    mage.dispose();

    final rogue = await _start('rogue');
    final hunter = _ahead(rogue, 'cow', 6.0)..target = rogue.player;
    rogue.actions.tap('ability2');
    _run(rogue, 0.05);
    expect(hunter.target, isNull, reason: 'it forgot the player');
    expect(rogue.player.graceLeft, greaterThan(2.9));
    expect(rogue.player.effects.has('speed'), isTrue);
    rogue.dispose();
  });

  test('the ranger\'s volleys loose arrows from the bag: eight around, five ahead', () async {
    final game = await _start('ranger');
    Iterable<Projectile> shots() => game.entities.whereType<Projectile>().where((s) => !s.removed);
    game.actions.tap('ability');
    _run(game, 0.02);
    expect(shots(), hasLength(8));
    expect(game.player.inventory.countOf('arrow'), 48 - 8);
    game.actions.tap('ability2');
    _run(game, 0.02);
    expect(shots(), hasLength(13));
    expect(game.player.inventory.countOf('arrow'), 48 - 13);
    game.dispose();
  });

  test('the staff spends mana on each bolt and will not cast short; the bow tires', () async {
    final mage = await _start('mage');
    final p = mage.player;
    p.selectedSlot = p.inventory.find('staff');
    mage.input.tap(VoxelAction.attack);
    _run(mage, 0.05);
    final classes = ClassSystem.of(mage);
    expect(classes.mana, closeTo(100.0 - 4.0, 0.2));
    _run(mage, 0.6);
    classes.mana = 1.0;
    mage.input.tap(VoxelAction.attack);
    _run(mage, 0.5);
    expect(mage.notices.feed.map((n) => n.text), contains('Not enough mana'));
    expect(classes.mana, greaterThan(1.0), reason: 'refused, nothing spent');
    mage.dispose();

    final ranger = await _start('ranger');
    ranger.player.selectedSlot = ranger.player.inventory.find('bow');
    ranger.input.tap(VoxelAction.attack);
    _run(ranger, 0.05);
    expect(ClassSystem.of(ranger).stamina, closeTo(120.0 - 3.0, 1.0));
    ranger.dispose();
  });

  test('the dodge dashes untouchable and waits; a level is a talent point, which buys a rank', () async {
    final game = await _start('rogue');
    final p = game.player;
    final classes = ClassSystem.of(game);
    game.actions.tap('dodge');
    _run(game, 0.05);
    expect(classes.dodging, isTrue);
    expect(classes.stamina, closeTo(140.0 - ClassSystem.dodgeCost, 0.5));
    expect(p.graceLeft, greaterThan(0.3));
    expect(Vector3(p.velocity.x, 0.0, p.velocity.z).length, closeTo(ClassSystem.dodgeSpeed, 0.5));
    game.actions.tap('dodge');
    _run(game, 0.05);
    expect(classes.stamina, greaterThan(140.0 - 2 * ClassSystem.dodgeCost), reason: 'one dodge at a time');

    expect(classes.learn('vitality'), isFalse, reason: 'no point yet');
    p.gainXp(gameSpec.player.xp!.toNext(0));
    _run(game, 0.02);
    expect(classes.points, 1);
    expect(game.notices.feed.map((n) => n.text), contains('Level 1! Talent point earned (J)'));
    final most = p.maxHp;
    expect(classes.learn('vitality'), isTrue);
    expect(p.maxHp, most + 4.0);
    expect(classes.rank('vitality'), 1);
    expect(classes.points, 0);
    expect(p.damageMultiplier, closeTo(1.1 * (1.0 + ClassSystem.levelDamage), 1e-9), reason: 'the level\'s share');
    game.dispose();
  });

  test('the class\'s numbers are saved with the world and come back', () async {
    final dir = Directory.systemTemp.createTempSync('class_system');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final game = await _start('mage');
    final classes = ClassSystem.of(game)
      ..points = 2
      ..stamina = 40.0
      ..mana = 12.0;
    expect(classes.learn('focus'), isTrue);
    saves.save(game, 'kept');
    game.dispose();

    final back = await _start('mage', save: saves.read('kept'));
    final again = ClassSystem.of(back);
    expect(again.points, 1);
    expect(again.rank('focus'), 1);
    expect(again.manaCost(20.0), closeTo(17.0, 1e-9));
    expect(again.stamina, greaterThan(40.0), reason: 'saved, then rested since');
    expect(again.mana, lessThan(20.0));
    back.dispose();
  });
}
