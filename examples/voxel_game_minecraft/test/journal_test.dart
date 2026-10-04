import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/classes/class_system.dart';
import 'package:voxel_game_minecraft/src/journal/achievement_table.dart';
import 'package:voxel_game_minecraft/src/journal/achievements.dart';
import 'package:voxel_game_minecraft/src/journal/bestiary.dart';
import 'package:voxel_game_minecraft/src/journal/game_stats.dart';
import 'package:voxel_game_minecraft/src/journal/quest.dart';
import 'package:voxel_game_minecraft/src/journal/quest_chain.dart';
import 'package:voxel_game_minecraft/src/journal/quest_log.dart';
import 'package:voxel_game_minecraft/src/journal/tutorial.dart';
import 'package:voxel_game_minecraft/src/journal/tutorial_steps.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/spec/game_title.dart';
import 'package:voxel_game_minecraft/src/spec/mob_table.dart';

/// A warrior's game, the tutorial [tutorial], as the title starts one.
Future<VoxelGame> _start({String tutorial = 'off', SavedWorld? save}) async {
  final options = {'class': 'warrior', 'tutorial': tutorial};
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

/// A creature of [id] beside the player, killed by them.
Mob _slay(VoxelGame game, String id) {
  final p = game.player;
  final mob = game.spawnMob(id, p.position + p.flatForward * 3.0 + Vector3(0.0, 0.5, 0.0));
  mob.takeDamage(Damage(10000.0, from: p.position, attacker: p));
  _run(game, 0.05);
  expect(mob.isDead, isTrue);
  return mob;
}

Recipe _recipe(String result) => gameSpec.recipes.firstWhere((r) => r.result == result);

Iterable<String> _told(VoxelGame game) => game.notices.feed.map((n) => n.text);

void main() {
  test('every quest, achievement and tutorial step names what the game declares, each once', () async {
    final game = await _start();
    for (final q in questChain) {
      for (final item in q.items.keys) {
        expect(game.items.has(item), isTrue, reason: '${q.id} gives $item');
      }
      for (final t in q.targets) {
        final known = q.goal == QuestGoal.kill ? plainKinds.containsKey(t) : game.items.has(t);
        expect(known, isTrue, reason: '${q.id} counts $t');
      }
      expect(q.targets.isEmpty, q.goal == QuestGoal.level, reason: q.id);
    }
    expect(questChain.map((q) => q.id).toSet(), hasLength(questChain.length));
    expect(achievementTable.map((a) => a.id).toSet(), hasLength(achievementTable.length));
    expect(tutorialSteps.map((s) => s.id).toSet(), hasLength(tutorialSteps.length));
    expect(
      [
        for (final a in achievementTable)
          if (a.on == null && a.when == null) a.id,
      ],
      ['traveler', 'underworld'],
      reason: 'unlocked by the waypoints and the fortress (VA-Zl)',
    );
    expect(() => Achievements.of(game).unlock(game, 'nope'), throwsArgumentError);
    expect(tutorialOption.join, isTrue, reason: 'a player joining picks for themself');
    expect(gameTitle(credits: const []).worldOptions, contains(tutorialOption));
    game.dispose();
  });

  test('the stats count what the player does, and what they walk', () async {
    final game = await _start();
    final stats = GameStats.of(game);
    final played = stats.playTime;
    game
      ..raise(const BlockBroken('stone', IVec3(0, 0, 0)))
      ..raise(const BlockBroken('dirt', IVec3(1, 0, 0)))
      ..raise(const BlockPlaced('stone', IVec3(0, 0, 0)))
      ..raise(const PlayerDied(null))
      ..raise(Travelled('world', 'underworld', through: gameSpec.portals.single))
      ..raise(const Travelled('underworld', 'world'))
      ..raise(ItemCrafted(_recipe('stick')));
    _slay(game, 'cow');
    game.input.hold(VoxelAction.moveForward, true);
    _run(game, 2.0);
    game.input.hold(VoxelAction.moveForward, false);
    expect(
      (stats.blocksBroken, stats.blocksPlaced, stats.deaths, stats.trips, stats.crafted, stats.kills),
      (2, 1, 1, 1, 1, 1),
      reason: 'a respawn\'s trip home is no trip',
    );
    expect(stats.walked, inInclusiveRange(4.0, 2.0 * game.player.spec.walkSpeed * 1.5));
    expect(stats.playTime - played, closeTo(2.05, 0.05));
    expect(GameStats.timeLabel(3725.0), '1h 02m');
    expect(GameStats.timeLabel(245.0), '4m 05s');
    game.dispose();
  });

  test('the bestiary meets what is around and counts a kill as its kind, an elite as the creature it twists', () async {
    final game = await _start();
    final b = Bestiary.of(game);
    final p = game.player;
    game.spawnMob('pig', p.position + Vector3(4.0, 0.5, 0.0));
    _run(game, Bestiary.lookEvery);
    expect(b.met('pig'), isTrue);
    expect(b.killsOf('pig'), 0);
    _slay(game, 'swift_zombie');
    expect(b.killsOf('zombie'), 1);
    expect(b.met('zombie'), isTrue);
    expect(b.kills.containsKey('swift_zombie'), isFalse);
    expect(Bestiary.kinds.map((s) => s.id), isNot(contains('villager')));
    expect(Bestiary.kinds.map((s) => s.id), isNot(contains('swift_zombie')));
    game.dispose();
  });

  test('a quest counts off its events, pays its experience and items, and the next one starts from nothing', () async {
    final game = await _start();
    final log = QuestLog.of(game);
    final p = game.player;
    expect(log.current!.id, 'wood');
    final apples = p.inventory.countOf('apple');
    p.pickUp('oak_log', 5);
    p.pickUp('dirt', 3);
    _run(game, 0.05);
    expect(log.progressOf(game), 5);
    p.pickUp('spruce_log', 6);
    _run(game, 0.05);
    expect(log.current!.id, 'table', reason: '11 of 8: the three over are not carried');
    expect(log.progressOf(game), 0);
    expect(p.inventory.countOf('apple'), apples + 2);
    expect(p.xp, 20);
    expect(_told(game), containsAll(['Quest complete: Gather wood!', 'New quest: Set up a workbench']));

    p.inventory.add('oak_planks', 4);
    expect(p.craft(_recipe('crafting_table')), isTrue);
    _run(game, 0.05);
    expect(log.current!.id, 'stone_pick');

    log.index = questChain.indexWhere((q) => q.id == 'night');
    _slay(game, 'cow');
    expect(log.progressOf(game), 0, reason: 'a cow is no monster of the quest');
    _slay(game, 'swift_zombie');
    expect(log.progressOf(game), 1, reason: 'an elite zombie is a zombie');

    log
      ..index = questChain.indexWhere((q) => q.id == 'glider')
      ..counted = 0;
    _run(game, 0.05);
    expect(log.current!.id, 'glider');
    p.inventory.add('glider', 1);
    _run(game, 0.05);
    expect(log.current!.id, 'troll', reason: 'carried, read off the bag');

    log.index = questChain.indexWhere((q) => q.id == 'level10');
    p.gainXp(100000);
    _run(game, 0.05);
    expect(log.current, isNull);
    expect(p.inventory.countOf('diamond_armor'), 1);
    game.dispose();
  });

  test('achievements unlock on their events and their states, told once', () async {
    final game = await _start();
    final a = Achievements.of(game);
    final p = game.player;
    expect(a.unlocked, isEmpty);
    game.raise(const BlockBroken('stone', IVec3(0, 0, 0)));
    _run(game, 0.05);
    expect(a.has('first_block'), isTrue);
    game.raise(const BlockBroken('stone', IVec3(0, 0, 0)));
    _run(game, 0.05);
    expect(_told(game).where((t) => t == 'Achievement: Getting Wood'), hasLength(1));

    _slay(game, 'cow');
    expect(a.has('first_kill'), isFalse, reason: 'a cow is no monster');
    _slay(game, 'swift_zombie');
    expect(a.has('first_kill') && a.has('elite'), isTrue);
    _slay(game, 'yeti');
    expect(a.has('boss'), isTrue);

    GameStats.of(game).blocksPlaced = 100;
    p.pickUp('diamond', 1);
    final classes = ClassSystem.of(game)..points = 1;
    classes.learn('vitality');
    p.gainXp(100000);
    _run(game, 0.05);
    expect(['builder', 'diamonds', 'talent', 'level_5', 'level_10'].where((id) => !a.has(id)), isEmpty);
    expect(a.has('deep'), isFalse);
    // A hollow down in the rock, and the player in it.
    final at = IVec3.floor(p.position);
    final cave = IVec3(at.x, deepUnder.toInt() - 4, at.z);
    for (var dy = 0; dy < 3; dy++) {
      game.world.setBlockNamed(IVec3(cave.x, cave.y + dy, cave.z), 'air');
    }
    p.position.setValues(cave.x + 0.5, cave.y + 0.01, cave.z + 0.5);
    game.step(1 / 60);
    expect(p.position.y, lessThan(deepUnder));
    expect(a.has('deep'), isTrue);
    game.dispose();
  });

  test('the tutorial moves on only on its step\'s own deed, and ends on the journal', () async {
    final game = await _start(tutorial: 'on');
    final t = Tutorial.of(game);
    final p = game.player;
    expect(t.current!.id, 'move');
    game.raise(const BlockBroken('stone', IVec3(0, 0, 0)));
    _run(game, 0.05);
    expect(t.current!.id, 'move', reason: 'a later step\'s deed does nothing yet');
    game.input.hold(VoxelAction.moveForward, true);
    _run(game, 1.0);
    game.input.hold(VoxelAction.moveForward, false);
    expect(t.current!.id, 'look');
    p.yaw += 1.0;
    game.step(1 / 60);
    expect(t.current!.id, 'jump');
    game.input.tap(VoxelAction.jump);
    game.step(1 / 60);
    expect(t.current!.id, 'break');
    game.raise(const BlockBroken('stone', IVec3(0, 0, 0)));
    game.step(1 / 60);
    game.openScreen(const BagScreen());
    game.step(1 / 60);
    expect(t.current!.id, 'craft');
    game.raise(ItemCrafted(_recipe('stick')));
    game.step(1 / 60);
    expect(t.current!.id, 'craft', reason: 'a stick is no tool');
    game.raise(ItemCrafted(_recipe('wooden_pickaxe')));
    game.step(1 / 60);
    game.closeScreen();
    game.raise(const BlockPlaced('dirt', IVec3(0, 0, 0)));
    game.raise(const FoodEaten('apple'));
    game.step(1 / 60);
    expect(t.current!.id, 'sleep');
    // A step and a half of the clock before sunrise.
    game.timeOfDay = 0.25 - 1.5 / 60.0 / game.spec.sky.dayLength;
    game.step(1 / 60);
    game.step(1 / 60);
    expect(t.current!.id, 'journal', reason: 'the night lived through');
    game.actions.tap('journal');
    game.step(1 / 60);
    expect(game.screen.value, const DeclaredScreen('journal'));
    game.step(1 / 60);
    expect(t.current, isNull);
    expect(_told(game), contains('Tutorial complete. Go explore!'));
    game.dispose();
  });

  test('a world made without the tutorial has none; one with it skips it on F6', () async {
    final off = await _start();
    expect(Tutorial.of(off).current, isNull);
    off.dispose();
    final on = await _start(tutorial: 'on');
    on.actions.tap(Tutorial.skipAction);
    on.step(1 / 60);
    expect(Tutorial.of(on).current, isNull);
    expect(_told(on), contains('Tutorial skipped.'));
    on.dispose();
    final none = await VoxelGame.startHeadless(gameSpec, options: const {'class': 'warrior'});
    expect(() => Tutorial.of(none), throwsArgumentError, reason: 'the title always offers it');
    none.dispose();
  });

  test('the journal\'s counts are saved with the world and come back', () async {
    final dir = Directory.systemTemp.createTempSync('journal');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final game = await _start(tutorial: 'on');
    game
      ..raise(const BlockBroken('stone', IVec3(0, 0, 0)))
      ..raise(const BlockPlaced('stone', IVec3(0, 0, 0)));
    _slay(game, 'swift_zombie');
    game.player.pickUp('oak_log', 3);
    _run(game, 0.05);
    final stats = GameStats.of(game);
    final played = stats.playTime;
    saves.save(game, 'kept');
    game.dispose();

    final back = await _start(tutorial: 'on', save: saves.read('kept'));
    final again = GameStats.of(back);
    expect((again.blocksBroken, again.blocksPlaced, again.kills), (1, 1, 1));
    expect(again.playTime, greaterThan(played));
    expect(Bestiary.of(back).killsOf('zombie'), 1);
    expect(QuestLog.of(back).progressOf(back), 3);
    expect(Achievements.of(back).unlocked, containsAll(['first_block', 'first_kill', 'elite']));
    expect(Tutorial.of(back).current!.id, 'move', reason: 'the step it was at');
    back.dispose();
  });
}
