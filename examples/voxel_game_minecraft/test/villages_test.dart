import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/villages/trade_screen.dart';
import 'package:voxel_game_minecraft/src/villages/trade_table.dart';
import 'package:voxel_game_minecraft/src/villages/villages.dart';

const _options = {'class': 'warrior'};

final VoxelGameSpec _spec = gameSpec.copyWith(player: gameSpec.playerWith(_options));

/// A warrior's game with no tutorial, as the title starts one; from [save]
/// when given.
Future<VoxelGame> _start({SavedWorld? save}) async {
  final game = await VoxelGame.startHeadless(_spec, options: _options, save: save);
  game.spawner.enabled = false;
  await _until(game, () => game.ready);
  return game;
}

/// Frames until [done], the workers given time to load the world.
Future<void> _until(VoxelGame game, bool Function() done, {void Function()? each}) async {
  for (var i = 0; i < 6000 && !done(); i++) {
    each?.call();
    game.frame(1 / 60);
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(done(), isTrue);
}

void _run(VoxelGame game, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.step(1 / 60);
  }
}

/// The village nearest the spawn.
PlacedStructure _nearestVillage(VoxelGame game) {
  final p = game.player.position;
  final found = {
    for (var cx = -48; cx <= 48; cx += 4)
      for (var cz = -48; cz <= 48; cz += 4)
        for (final s in game.world.generator.structuresNear(cx, cz))
          if (s.name == Villages.structure) s,
  }.toList()..sort((a, b) => _flat(a).distanceTo(p).compareTo(_flat(b).distanceTo(p)));
  return found.first;
}

Vector3 _flat(PlacedStructure s) => Vector3(s.x + 0.5, 0, s.z + 0.5);

/// Stands the player [metres] east of [village]'s centre, kept there until
/// the world is loaded about it (and the village, when within its reach),
/// and lets the villages look.
Future<void> _standBy(VoxelGame game, PlacedStructure village, double metres) async {
  final x = village.x + metres, z = village.z.toDouble();
  final above = Vector3(x + 0.5, village.y + 20.0, z + 0.5);
  final centre = IVec3(village.x, village.y, village.z);
  await _until(
    game,
    () => game.world.isLoaded(IVec3.floor(above)) && (metres >= Villages.reach || game.world.isLoaded(centre)),
    each: () => game.player.placeAt(above),
  );
  game.player.placeAt(Vector3(x + 0.5, game.world.groundHeight(x.floor(), z.floor()).toDouble(), z + 0.5));
  _run(game, Villages.lookEvery + 0.1);
}

/// A game whose nearest village is peopled.
Future<(VoxelGame, PlacedStructure)> _peopled() async {
  final game = await _start();
  final village = _nearestVillage(game);
  await _standBy(game, village, 20.0);
  expect(Villages.villagersIn(game), isNotEmpty);
  return (game, village);
}

Iterable<String> _told(VoxelGame game) => game.notices.feed.map((n) => n.text);

void main() {
  test('every offer is of items the game has', () {
    final items = _spec.buildItems(_spec.buildBlocks());
    for (final o in tradeTable) {
      expect(items.has(o.take), isTrue, reason: o.take);
      expect(items.has(o.give), isTrue, reason: o.give);
    }
  });

  test('a village is peopled once, when the player comes near: 3 to 5 villagers about its centre', () async {
    final game = await _start();
    final villages = Villages.of(game);
    final village = _nearestVillage(game);
    await _standBy(game, village, Villages.reach + 20.0);
    expect(villages.peopled, isEmpty, reason: 'too far yet');
    await _standBy(game, village, 20.0);
    final centre = IVec3(village.x, village.y, village.z);
    expect(villages.peopled, {centre});
    final people = game.mobs.where((m) => m.spec.id == Villages.villager).toList();
    expect(people.length, inInclusiveRange(Villages.fewest, Villages.most));
    expect(Villages.villagersIn(game), unorderedEquals(people));
    for (final m in people) {
      final offers = Villages.offersOf(game, m);
      expect(Vector3(m.position.x, 0, m.position.z).distanceTo(_flat(village)), closeTo(Villages.ring, 0.5));
      expect(m.home.x, village.x + 0.5);
      expect(m.home.z, village.z + 0.5);
      expect(offers.toSet(), hasLength(Villages.offerCount), reason: 'distinct');
      expect(tradeTable, containsAll(offers));
    }
    expect(_told(game), contains('A village! Use a villager to trade'));
    await _standBy(game, village, 10.0);
    expect(game.mobs.where((m) => m.spec.id == Villages.villager), hasLength(people.length), reason: 'once');
    game.dispose();
  });

  test('a villager takes no harm and keeps to its village', () async {
    final (game, village) = await _peopled();
    final m = Villages.villagersIn(game).first;
    m.takeDamage(Damage(100, attacker: game.player, from: game.player.position, knockback: 6.0));
    _run(game, 20.0);
    expect(m.isDead, isFalse);
    expect(m.hp, m.maxHp);
    expect(Vector3(m.position.x, 0, m.position.z).distanceTo(_flat(village)), lessThan(16.0 + 2.0));
    game.dispose();
  });

  test("a villager's use opens its trade; a trade takes the price and gives the goods, or nothing", () async {
    final (game, _) = await _peopled();
    final villages = Villages.of(game);
    final m = Villages.villagersIn(game).first;
    final offers = Villages.offersOf(game, m);
    gameSpec.mobUses[Villages.villager]!(game, m);
    expect(game.screen.value, isA<DeclaredScreen>().having((s) => s.id, 'id', Villages.screen));
    expect(villages.open.name, 'Villager');
    expect(villages.open.offers, offers);

    final bag = game.player.inventory;
    for (var i = 0; i < bag.slots.length; i++) {
      bag.setSlot(i, null);
    }
    final o = offers.first;
    bag.add(o.take, o.takeCount - 1);
    expect(villages.trade(game, 0), isFalse, reason: 'one short');
    expect(bag.countOf(o.take), o.takeCount - 1);
    bag.add(o.take, 1);
    expect(villages.trade(game, 0), isTrue);
    expect(bag.countOf(o.take), 0);
    expect(bag.countOf(o.give), o.giveCount);
    expect(villages.trade(game, 0), isFalse, reason: 'no restock needed, but the price again');

    // A bag full of stone: the price is there, the room is not.
    for (var i = 0; i < bag.slots.length; i++) {
      bag.setSlot(i, ItemStack('stone', game.items['stone'].stack));
    }
    bag.setSlot(0, ItemStack(o.take, o.takeCount));
    expect(villages.trade(game, 0), isFalse, reason: 'no room for what it gives');
    expect(bag.countOf(o.take), o.takeCount);
    expect(() => villages.trade(game, Villages.offerCount), throwsRangeError);
    game.dispose();
  });

  test("the save keeps the villages peopled, and each villager its offers and home, as a trip does", () async {
    final dir = Directory.systemTemp.createTempSync('villages');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final (game, _) = await _peopled();
    final villages = Villages.of(game);
    // Shoved off the ring, so each one is told by where it stands now.
    for (final m in Villages.villagersIn(game)) {
      m.takeDamage(Damage(1, from: m.home, knockback: 4.0));
    }
    _run(game, 1.0);
    final before = {
      for (final m in Villages.villagersIn(game))
        m.position.clone(): (home: m.home.clone(), offers: Villages.offersOf(game, m)),
    };
    final peopled = villages.peopled;
    saves.save(game, 'village');
    game.dispose();

    final loaded = await _start(save: saves.read('village'));
    expect(Villages.of(loaded).peopled, peopled);
    void expectAsBefore() {
      final back = Villages.villagersIn(loaded).toList();
      expect(back, hasLength(before.length));
      for (final m in back) {
        final was = before.entries.firstWhere((b) => b.key.distanceTo(m.position) < 1e-6).value;
        expect(Villages.offersOf(loaded, m), was.offers);
        expect(m.home, was.home, reason: 'it strolls about its village, not where it was saved');
      }
    }

    expectAsBefore();
    loaded.travel('underworld');
    expect(Villages.villagersIn(loaded), isEmpty);
    await _until(loaded, () => loaded.travelState is! Arriving);
    loaded.travel('world');
    expectAsBefore();

    Villages.villagersIn(loaded).first.data.remove(Villages.offersKey);
    expect(
      () => Villages().restore(loaded, {'villages': <Object?>[]}),
      throwsFormatException,
      reason: 'a villager with no offers',
    );
    loaded.dispose();
  });

  test("on a client, a villager's use asks the host, and its trade opens with the host's offers", () async {
    final (host, _) = await _peopled();
    final session = await host.host(port: 0);
    final client = await VoxelGame.joinGame(
      _spec,
      '127.0.0.1',
      port: session.net.port,
      headless: true,
      options: _options,
    );
    Mob? replica;
    await _until(client, () {
      host.frame(1 / 60);
      replica = client.mobs.where((m) => m.spec.id == Villages.villager).firstOrNull;
      return client.ready && replica != null;
    });
    final r = replica!;
    expect(r.replica, isTrue);
    expect(r.data, isEmpty, reason: 'the host keeps the offers');
    Villages.use(client, r);
    expect(client.screen.value, isNull, reason: 'not before the answer');
    await _until(client, () {
      host.frame(1 / 60);
      return client.screen.value != null;
    });
    final theirs = Villages.offersOf(host, host.mobs.firstWhere((m) => m.netId == r.netId));
    expect(Villages.of(client).open.name, 'Villager');
    expect(Villages.of(client).open.offers, theirs);
    final o = theirs.first;
    final bag = client.player.inventory;
    bag.add(o.take, o.takeCount);
    final had = bag.countOf(o.give);
    expect(Villages.of(client).trade(client, 0), isTrue, reason: "the client's own bag");
    expect(bag.countOf(o.give), had + o.giveCount);
    await client.session!.close();
    await session.close();
    client.dispose();
    host.dispose();
  });

  testWidgets('the trade screen: a row an offer, what the bag holds, and a tap trades', (tester) async {
    late VoxelGame game;
    await tester.runAsync(() async => (game, _) = await _peopled());
    final villages = Villages.of(game);
    final m = Villages.villagersIn(game).first;
    Villages.use(game, m);
    final o = villages.open.offers.first;
    final bag = game.player.inventory;
    bag.remove(o.take, bag.countOf(o.take));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: (c) => TradeScreen.builder(c, game))),
      ),
    );
    await tester.pump();
    expect(find.text("Villager's trades"), findsOneWidget);
    final short = '${game.items[o.take].name} (you have 0)';
    expect(find.text(short), findsWidgets);
    bag.add(o.take, o.takeCount);
    game.frame(1 / 60);
    await tester.pump();
    final enough = '${game.items[o.take].name} (you have ${o.takeCount})';
    await tester.tap(find.text(enough).first);
    await tester.pump();
    expect(bag.countOf(o.give), greaterThanOrEqualTo(o.giveCount));
    expect(bag.countOf(o.take), 0);
    game.dispose();
  });
}
