import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/classes/class_system.dart';
import 'package:voxel_game_minecraft/src/enchanting/enchanting.dart';
import 'package:voxel_game_minecraft/src/journal/achievements.dart';
import 'package:voxel_game_minecraft/src/journal/journal_screen.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/waypoints/waypoints.dart';

/// A warrior's game with no tutorial, as the title starts one.
Future<VoxelGame> _start() async {
  final options = {'class': 'warrior'};
  final game = await VoxelGame.startHeadless(gameSpec.copyWith(player: gameSpec.playerWith(options)), options: options);
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

/// A waypoint placed [dx] blocks east of the player, as the player places one.
IVec3 _place(VoxelGame game, int dx) {
  final p = IVec3.floor(game.player.position);
  final cell = IVec3(p.x + dx, game.world.groundHeight(p.x + dx, p.z) + 1, p.z);
  game.world.setBlockNamed(cell, Waypoints.block);
  game.raise(BlockPlaced(Waypoints.block, cell));
  _run(game, 1 / 60);
  return cell;
}

Iterable<String> _told(VoxelGame game) => game.notices.feed.map((n) => n.text);

void main() {
  test('a waypoint placed is named and listed; one broken, or found gone, is forgotten', () async {
    final game = await _start();
    final w = Waypoints.of(game);
    final a = _place(game, 2);
    final b = _place(game, 4);
    expect(w.all.map((p) => p.label), ['Waypoint 1', 'Waypoint 2']);
    expect(w.all.first.dimension, game.dimension);
    expect(_told(game), contains('Waypoint 1 set. Use it to travel (J lists them)'));
    game.world.setBlockNamed(a, 'air');
    game.raise(BlockBroken(Waypoints.block, a));
    _run(game, 1 / 60);
    expect(w.all.map((p) => p.label), ['Waypoint 2']);
    expect(_place(game, 6), isNot(a));
    expect(w.all.map((p) => p.label), ['Waypoint 1', 'Waypoint 2'], reason: 'the first free number');
    // Blown up: no break is raised, and a look at the loaded world finds it gone.
    game.world.setBlockNamed(b, 'air');
    _run(game, Waypoints.lookEvery + 0.1);
    expect(w.all.map((p) => p.label), ['Waypoint 1']);
    game.dispose();
  });

  test('a trip is free beside a waypoint, costs mana from afar, and stands the player on the waypoint', () async {
    final game = await _start();
    final w = Waypoints.of(game);
    final classes = ClassSystem.of(game);
    _place(game, 2);
    final far = _place(game, 40);
    final there = w.all.firstWhere((p) => p.cell == far);
    classes.mana = 0.0;
    expect(w.travel(game, there), isTrue, reason: 'beside Waypoint 1');
    expect(classes.mana, 0.0);
    _run(game, 0.5);
    expect(game.player.position.x, closeTo(far.x + 0.5, 0.3));
    expect(game.player.position.z, closeTo(far.z + 0.5, 0.3));
    expect(_told(game), contains('Travelled to ${there.label}'));
    expect(Achievements.of(game).has('traveler'), isTrue);
    // From afar: walk off 20 m first.
    game.player.placeAt(game.player.position + Vector3(0, 0, 20));
    final home = w.all.firstWhere((p) => p.cell != far);
    classes.mana = Waypoints.cost - 1.0;
    expect(w.travel(game, home), isFalse);
    expect(_told(game), contains('Need 10 mana to travel from afar'));
    classes.mana = Waypoints.cost + 2.0;
    expect(w.travel(game, home), isTrue);
    expect(classes.mana, closeTo(2.0, 1e-9));
    game.dispose();
  });

  test('a waypoint of another world is not travelled to; the waypoints come back with the save', () async {
    final game = await _start();
    final w = Waypoints.of(game);
    _place(game, 3);
    final elsewhere = (cell: const IVec3(0, 40, 0), dimension: 'underworld', label: 'Deep');
    expect(w.travel(game, elsewhere), isFalse);
    final saved = w.save(game);
    final copy = Waypoints()..restore(game, saved);
    expect(copy.all, w.all);
    expect(
      () => Waypoints().restore(game, [
        {
          'cell': [0, 0, 0],
          'dimension': 'moon',
          'label': 'X',
        },
      ]),
      throwsFormatException,
    );
    game.dispose();
  });

  test('using a waypoint opens the journal on its waypoints', () async {
    final game = await _start();
    final cell = _place(game, 2);
    gameSpec.blockUses[Waypoints.block]!(game, cell);
    expect(game.screen.value, isA<DeclaredScreen>().having((s) => s.id, 'id', Waypoints.screen));
    game.dispose();
  });

  test('an enchanting table adds 1 to 3 to the bonus in hand, for magic dust and a level', () async {
    final game = await _start();
    final p = game.player;
    final bag = p.inventory;
    final use = gameSpec.blockUses[Enchanting.table]!;
    final cell = IVec3.floor(p.position);
    bag.setSlot(p.selectedSlot, ItemStack('apple', 3));
    use(game, cell);
    expect(_told(game), contains('Hold a weapon or a tool to enchant it'));
    bag.setSlot(p.selectedSlot, ItemStack('iron_sword', 1));
    use(game, cell);
    expect(_told(game), contains('Enchanting takes a level'));
    p.level = 2;
    bag.remove(Enchanting.dustItem, bag.countOf(Enchanting.dustItem));
    bag.add(Enchanting.dustItem, 1);
    use(game, cell);
    expect(_told(game), contains('Enchanting takes 2 magic dust'));
    expect(bag.bonusAt(p.selectedSlot), 0, reason: 'nothing spent');
    bag.add(Enchanting.dustItem, 2);
    final gain = Enchanting.use(game, cell);
    expect(gain, inInclusiveRange(1, Enchanting.maxGain));
    expect(bag.bonusAt(p.selectedSlot), gain);
    expect(bag.idAt(p.selectedSlot), 'iron_sword');
    expect(bag.countOf(Enchanting.dustItem), 1);
    expect(p.level, 1);
    game.dispose();
  });

  testWidgets('the journal\'s waypoints: each with how far it is, and a tap travels there', (tester) async {
    late VoxelGame game;
    await tester.runAsync(() async => game = await _start());
    final far = _place(game, 30);
    _place(game, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: (c) => JournalScreen.waypointsBuilder(c, game))),
      ),
    );
    await tester.pumpAndSettle();
    final line = JournalScreen.waypointLine(game, Waypoints.of(game).all.first);
    expect(line, startsWith('Waypoint 1   (${far.x}, ${far.y}, ${far.z})   '));
    expect(find.text(line), findsOneWidget);
    game.openScreen(const DeclaredScreen(Waypoints.screen));
    await tester.tap(find.text(line));
    await tester.pump();
    expect(game.screen.value, isNull, reason: 'the journal closes on a trip');
    expect(Achievements.of(game).has('traveler'), isTrue);
    game.dispose();
  });
}
