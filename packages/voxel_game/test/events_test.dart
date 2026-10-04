import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
  BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
  BlockType('planks', color: 0xB08850, hardness: 1.0, tool: 'axe'),
  BlockType.liquid('water', color: 0x3366CC),
  BlockType.liquid('water_flow', color: 0x3366CC, kind: 'water', source: false),
];

const _cow = MobSpec('cow', hp: 4, speed: 1.0, brain: [Wander()]);

const _planks = Recipe('planks', 4, {'dirt': 1});

/// Level grass at y 20, no caves, a cow, an apple, a recipe and experience.
VoxelGameSpec _spec({List<GameSystem> Function() systems = VoxelGameSpec.noSystems}) => VoxelGameSpec(
  blocks: _blocks,
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  items: const [ItemType('apple', color: 0xD03020, food: Food(heal: 2.0))],
  recipes: const [_planks],
  player: const PlayerSpec(startingItems: {'planks': 3, 'apple': 2}, xp: XpSpec()),
  mobs: const [_cow],
  sky: SkySpec.alwaysDay,
  systems: systems,
);

Future<VoxelGame> _start(VoxelGameSpec spec, {SavedWorld? save, WorldInfo? info}) async {
  final game = await VoxelGame.startHeadless(spec, save: save, info: info);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
  return game;
}

Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

/// A system that writes down every event it hears, and in which step.
class _Log extends GameSystem {
  final List<GameEvent> events = [];
  int steps = 0;
  final List<int> heardAt = [];

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    events.add(event);
    heardAt.add(steps);
  }

  @override
  void tick(VoxelGame game, double dt) => steps++;
}

/// Counts the blocks the player broke, kept in the save under [saveKey].
class _Tally extends SavedSystem {
  _Tally([this.saveKey = 'tally']);

  @override
  final String saveKey;

  int broken = 0;
  bool restored = false;

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    if (event is BlockBroken) broken++;
  }

  @override
  Object? save(VoxelGame game) => {'broken': broken};

  @override
  void restore(VoxelGame game, Object? saved) {
    broken = (saved! as Map<String, Object?>)['broken']! as int;
    restored = true;
  }
}

void main() {
  group('events', () {
    test('a place, a break and the pickup are heard by every system, in order, in the step', () async {
      final a = _Log(), b = _Log();
      final game = await _start(_spec(systems: () => [a, b]));
      final p = game.player;
      p.pitch = -0.9;
      p.selectedSlot = p.inventory.find('planks');
      await _run(game, 0.2);
      final aimed = p.aimedBlock!;
      game.input.tap(VoxelAction.use);
      await _run(game, 0.1);
      final placed = a.events.whereType<BlockPlaced>().single;
      expect((placed.block, placed.cell), ('planks', aimed.block + aimed.normal));

      p.pitch = -1.5; // straight down
      game.input.hold(VoxelAction.attack, true);
      for (var i = 0; i < 180 && a.events.whereType<BlockBroken>().isEmpty; i++) {
        await _run(game, 1 / 60);
      }
      game.input.hold(VoxelAction.attack, false);
      final broken = a.events.whereType<BlockBroken>().single;
      expect(broken.block, 'grass');
      await _run(game, 1.5);
      final picked = a.events.whereType<ItemPickedUp>().single;
      expect((picked.item, picked.count), ('dirt', 1));
      expect(a.events.indexOf(placed), lessThan(a.events.indexOf(broken)));
      expect(a.events.indexOf(broken), lessThan(a.events.indexOf(picked)));
      expect(b.events, a.events, reason: 'every system hears every event');
    });

    test('an event raised between steps waits for the systems\' turn of the next', () async {
      final log = _Log();
      final game = await _start(_spec(systems: () => [log]));
      final steps = log.steps;
      game.openScreen(const BagScreen());
      expect(log.events, isEmpty, reason: 'not heard where it was raised');
      game.step(1 / 60);
      expect(log.events.single, isA<ScreenOpened>().having((e) => e.screen, 'screen', isA<BagScreen>()));
      expect(log.heardAt.single, steps, reason: 'heard before the systems tick');
    });

    test('kills, a craft, a meal, two levels and a death of its blow', () async {
      final log = _Log();
      final game = await _start(_spec(systems: () => [log]));
      final p = game.player;
      final mine = game.spawnMob('cow', p.position + Vector3(3, 0, 0));
      mine.takeDamage(Damage(10.0, attacker: p));
      final wild = game.spawnMob('cow', p.position + Vector3(-3, 0, 0))..kill();
      p.inventory.add('dirt', 1);
      expect(p.craft(_planks), isTrue);
      expect(p.craft(_planks), isFalse, reason: 'no dirt left: nothing crafted, nothing heard');
      p.hp = 10.0;
      p.selectedSlot = p.inventory.find('apple');
      expect(p.eatHeld(), isTrue);
      p.gainXp(150);
      p.takeDamage(const Damage(100.0, source: 'lava'));
      game.step(1 / 60);

      final kills = log.events.whereType<MobKilled>().toList();
      expect(kills.map((k) => (k.mob, k.byPlayer)), [(mine, true), (wild, false)]);
      expect(log.events.whereType<ItemCrafted>().single.recipe, same(_planks));
      expect(log.events.whereType<FoodEaten>().single.item, 'apple');
      expect(log.events.whereType<LevelGained>().map((e) => e.level), [1, 2]);
      expect(log.events.whereType<PlayerDied>().single.cause?.source, 'lava');
      expect(log.events.whereType<ScreenOpened>(), isEmpty, reason: 'the death screen is the death');
    });

    test('a taming that took is heard, one that did not is not', () async {
      final log = _Log();
      final game = await _start(_spec(systems: () => [log]));
      game.player
        ..tamingTried(_cow, took: false)
        ..tamingTried(_cow, took: true);
      game.step(1 / 60);
      expect(log.events.whereType<Tamed>().single.species, same(_cow));
    });
  });

  group('systems', () {
    test('are made afresh for every game, and found by their type', () async {
      final spec = _spec(systems: () => [_Log(), _Tally()]);
      final one = await _start(spec), two = await _start(spec);
      expect(one.systems, hasLength(2));
      expect(one.system<_Tally>(), isNot(same(two.system<_Tally>())));
      expect(one.system<_Log>(), same(one.systems.first));
      expect(() => one.system<MobSpawner>(), throwsStateError, reason: 'none of that type');
    });

    test('two that save under one key throw when the game is made', () async {
      expect(() => VoxelGame.startHeadless(_spec(systems: () => [_Tally(), _Tally()])), throwsArgumentError);
    });

    test('a saving system writes its key under game.json\'s game, and a load puts it back raising nothing', () async {
      final dir = Directory.systemTemp.createTempSync('voxel_events');
      addTearDown(() => dir.deleteSync(recursive: true));
      final saves = WorldSaves(dir);
      final spec = _spec(systems: () => [_Tally(), _Log()]);
      final game = await _start(spec);
      game.system<_Tally>().broken = 5;
      game.player.kill();
      saves.save(game, 'kept');
      final json = jsonDecode(File('${dir.path}/kept/game.json').readAsStringSync()) as Map<String, Object?>;
      expect(json['version'], WorldSaves.stateVersion);
      expect(json['game'], {
        'tally': {'broken': 5},
      });

      final back = await VoxelGame.startHeadless(spec, save: saves.read('kept'));
      expect(back.system<_Tally>().broken, 5);
      expect(back.player.isDead, isTrue);
      back.step(1 / 60);
      expect(back.system<_Log>().events, isEmpty, reason: 'loading the dead player is no death');
    });

    test('a save from before version 8 loads with the systems as made; a key no system saves throws', () async {
      final dir = Directory.systemTemp.createTempSync('voxel_events');
      addTearDown(() => dir.deleteSync(recursive: true));
      final saves = WorldSaves(dir);
      final game = await _start(_spec(systems: () => [_Tally()]));
      game.system<_Tally>().broken = 2;
      saves.save(game, 'old');
      final file = File('${dir.path}/old/game.json');
      final s = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      file.writeAsStringSync(jsonEncode({...s, 'version': 7}..remove('game')));
      final old = await VoxelGame.startHeadless(_spec(systems: () => [_Tally()]), save: saves.read('old'));
      expect(old.system<_Tally>().restored, isFalse);
      expect(old.system<_Tally>().broken, 0);

      file.writeAsStringSync(jsonEncode(s));
      expect(
        () => VoxelGame.startHeadless(_spec(systems: () => [_Tally('other')]), save: saves.read('old')),
        throwsStateError,
      );
    });

    test('a game reads its slot\'s world, with the options it was made with', () async {
      const info = WorldInfo(slot: 'tower', name: 'Tower', seed: 1, saved: false, options: {'class': 'mage'});
      final game = await _start(info.applyTo(_spec()), info: info);
      expect(game.worldInfo?.options['class'], 'mage');
      expect((await _start(_spec())).worldInfo, isNull, reason: 'a game in no slot');
    });
  });
}
