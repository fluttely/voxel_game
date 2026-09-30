import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
  BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
  BlockType.liquid('water', color: 0x3366CC),
];

const _effects = [
  EffectType('regeneration', 'Regeneration', 0.9, 0.4, 0.6, period: 1.0, heal: 1.0),
  EffectType('poison', 'Poison', 0.3, 0.6, 0.2, period: 1.0, damage: 1.0, bad: true),
  EffectType('swiftness', 'Swiftness', 0.5, 0.8, 1.0, stats: {PlayerEntity.speedStat: StatModifier.multiply(0.5)}),
  EffectType('resistance', 'Resistance', 0.6, 0.6, 0.7, stats: {PlayerEntity.armorStat: StatModifier.add(5.0)}),
];

const _items = [
  ItemType('bowl', color: 0x8B5A2B),
  ItemType('apple', color: 0xD03020, food: Food(hunger: 4)),
  ItemType('stew', color: 0x9A6A3A, stack: 1, food: Food(hunger: 6, heal: 2.0, leaves: 'bowl')),
  ItemType('potion', color: 0xE040A0, food: Food(effect: 'regeneration', seconds: 5.0)),
  ItemType('tunic', color: 0xEEEEEE, stack: 1, armor: Armor('chest', 3)),
  ItemType('mail', color: 0xB0B0B8, stack: 1, armor: Armor('chest', 5)),
  ItemType('cap', color: 0xEEEEEE, stack: 1, armor: Armor('head', 1)),
];

/// Level grass at y 20, no caves, no trees, always day: nothing spawns.
VoxelGameSpec _flat({PlayerSpec player = const PlayerSpec()}) => VoxelGameSpec(
  blocks: _blocks,
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  items: _items,
  effects: _effects,
  player: player,
  sky: SkySpec.alwaysDay,
);

Future<VoxelGame> _start(VoxelGameSpec spec, {SavedWorld? save}) async {
  final game = await VoxelGame.startHeadless(spec, save: save);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue, reason: 'the spawn chunk loads and the player stands on it');
  return game;
}

/// [seconds] of simulation, letting the chunk jobs land between frames.
Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

/// Puts [item] in slot 0 and holds it.
void _hold(PlayerEntity p, String item, [int count = 1]) {
  p.inventory.setSlot(0, ItemStack(item, count));
  p.selectedSlot = 0;
}

const _fastHunger = HungerSpec(secondsPerPoint: 0.5, regenSeconds: 0.5, starveSeconds: 0.5);

void main() {
  test('with no hunger declared the bar never moves and food only heals', () async {
    final game = await _start(_flat());
    final p = game.player;
    expect(p.hunger, 0.0);
    await _run(game, 2.0);
    expect(p.hunger, 0.0);
    expect(p.hp, p.spec.hp, reason: 'an empty bar starves no one who has no hunger');
    expect(p.canEat(game.items['apple']), isFalse, reason: 'an apple only fills hunger');
    p.hp = 10.0;
    expect(p.canEat(game.items['stew']), isTrue, reason: 'a stew also heals');
  });

  test('hunger empties with time, a full bar heals and an empty one starves', () async {
    final game = await _start(_flat(player: const PlayerSpec(hunger: _fastHunger)));
    final p = game.player;
    expect(p.hunger, 20.0);
    p.hp = 10.0;
    await _run(game, 1.1);
    expect(p.hunger, closeTo(20.0 - 1.1 / 0.5, 0.1), reason: 'a point every half second');
    expect(p.hp, 12.0, reason: 'a full enough bar heals a point every half second');

    p.hunger = 3.0; // below regenAbove: neither heals nor starves
    await _run(game, 1.0);
    expect(p.hp, 12.0);

    p.hunger = 0.0;
    await _run(game, 1.1);
    expect(p.hp, 10.0, reason: 'a pang every half second, with no grace between them');
  });

  test('a creative player never gets hungry', () async {
    final game = await _start(_flat(player: const PlayerSpec(hunger: _fastHunger, creative: true)));
    await _run(game, 1.0);
    expect(game.player.hunger, 20.0);
  });

  test('the player eats what is in hand on a press, never a whole stack by holding', () async {
    final game = await _start(_flat(player: const PlayerSpec(hunger: HungerSpec())));
    final p = game.player;
    _hold(p, 'apple', 5);
    p.hunger = 20.0;
    expect(p.eatHeld(), isFalse, reason: 'a full bar eats nothing');
    expect(p.inventory.countOf('apple'), 5);

    p.hunger = 10.0;
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.inventory.countOf('apple'), 4);
    expect(p.hunger, closeTo(14.0, 0.01));

    game.input.hold(VoxelAction.use, true);
    await _run(game, 1.0);
    game.input.hold(VoxelAction.use, false);
    expect(p.inventory.countOf('apple'), 3, reason: 'the press eats one; holding on eats no more');
    expect(p.hunger, closeTo(18.0, 0.05));
  });

  test('a stew heals and leaves its bowl; a potion starts its effect, which heals by the tick', () async {
    final game = await _start(_flat(player: const PlayerSpec(hunger: HungerSpec())));
    final p = game.player;
    p
      ..hp = 10.0
      ..hunger = 10.0;
    _hold(p, 'stew');
    expect(p.eatHeld(), isTrue);
    expect(p.hp, 12.0);
    expect(p.hunger, closeTo(16.0, 0.01));
    expect(p.inventory.countOf('stew'), 0);
    expect(p.inventory.countOf('bowl'), 1);

    _hold(p, 'potion');
    expect(p.eatHeld(), isTrue);
    expect(p.effects.has('regeneration'), isTrue);
    await _run(game, 2.1);
    expect(p.hp, 14.0, reason: 'a point a second');
    await _run(game, 4.0);
    expect(p.effects.has('regeneration'), isFalse, reason: 'five seconds and it is gone');
  });

  test('an internal hurt goes through armour and the grace after a blow; a poison tick is one', () async {
    final game = await _start(_flat());
    final p = game.player;
    _hold(p, 'mail');
    expect(p.wearHeld(), isTrue);
    expect(p.takeDamage(const Damage(1.0)), closeTo(0.35, 1e-9), reason: 'five armour: the floor');
    expect(p.takeDamage(const Damage(1.0)), 0.0, reason: 'the grace after a blow');
    expect(p.takeDamage(const Damage(1.0, internal: true)), 1.0);
    await _run(game, 0.5);
    final before = p.hp;
    p.effects.apply('poison', 1.5);
    await _run(game, 1.05);
    expect(p.hp, closeTo(before - 1.0, 1e-9), reason: 'the whole point');
  });

  test('an effect bends the speed on foot', () async {
    final game = await _start(_flat());
    final p = game.player;
    await _run(game, 0.3);
    Future<double> walk() async {
      final from = p.position.clone();
      game.input.hold(VoxelAction.moveForward, true);
      await _run(game, 1.0);
      game.input.hold(VoxelAction.moveForward, false);
      await _run(game, 0.5);
      return ((p.position - from)..y = 0).length;
    }

    final plain = await walk();
    p.effects.apply('swiftness', 10.0);
    final swift = await walk();
    expect(swift / plain, closeTo(1.5, 0.1));
  });

  test('armour is put on from the hand, turns blows aside to a floor and swaps with what was worn', () async {
    final game = await _start(_flat());
    final p = game.player;
    _hold(p, 'tunic');
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.worn['chest']?.id, 'tunic');
    expect(p.inventory.isEmptySlot(0), isTrue);
    expect(p.armor, 3.0);

    expect(p.takeDamage(const Damage(10.0)), closeTo(10.0 - 3 * 0.4, 1e-9));
    await _run(game, 0.5);

    _hold(p, 'mail');
    expect(p.wearHeld(), isTrue);
    expect(p.worn['chest']?.id, 'mail');
    expect(p.inventory.idAt(0), 'tunic', reason: 'what was worn comes back into the hand');
    p.effects.apply('resistance', 10.0, 3.0);
    expect(p.armor, 20.0, reason: 'five worn and fifteen from the effect');
    p.hp = 20.0;
    expect(p.takeDamage(const Damage(10.0)), closeTo(3.5, 1e-9), reason: 'the floor: 35 % always lands');

    _hold(p, 'cap');
    expect(p.wearHeld(), isTrue);
    expect(p.takeOff('chest'), isTrue);
    expect(p.worn.keys, ['head']);
    expect(p.inventory.countOf('mail'), 1);
    expect(p.takeOff('chest'), isFalse, reason: 'nothing is worn there any more');
  });

  test('experience levels up by the curve and each level raises the most health', () async {
    final game = await _start(_flat(player: const PlayerSpec(xp: XpSpec(base: 10, exponent: 1, hpPerLevel: 2))));
    final p = game.player;
    expect(p.level, 0);
    p.gainXp(9);
    expect(p.level, 0);
    p.gainXp(1 + 20 + 5);
    expect(p.level, 2, reason: '10 to leave level 0, 20 to leave level 1');
    expect(p.xp, 5);
    expect(p.maxHp, 24.0);
    expect(p.hp, 24.0, reason: 'a level brings its health with it');

    final none = await _start(_flat());
    expect(() => none.player.gainXp(1), throwsStateError);
  });

  test('a starved player stands up again fed, with no effects on them', () async {
    final game = await _start(_flat(player: const PlayerSpec(hunger: _fastHunger, respawnSeconds: 0.5)));
    final p = game.player;
    p
      ..hunger = 0.0
      ..hp = 1.0;
    p.effects.apply('swiftness', 60.0);
    await _run(game, 0.6);
    expect(p.isDead, isTrue);
    await _run(game, 0.6);
    expect(p.isDead, isFalse);
    expect(p.hp, p.maxHp);
    expect(p.hunger, closeTo(20.0, 0.5), reason: 'full, less the steps since');
    expect(p.effects.rows, isEmpty);
  });

  test('a save keeps hunger, experience, effects and what is worn; a version 1 save still loads', () async {
    final dir = Directory.systemTemp.createTempSync('voxel_survival');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final spec = _flat(
      player: const PlayerSpec(hunger: HungerSpec(), xp: XpSpec()),
    );
    final game = await _start(spec);
    final p = game.player;
    p
      ..hunger = 7.5
      ..xp = 12
      ..level = 3;
    p.effects.apply('swiftness', 30.0, 2.0);
    _hold(p, 'tunic');
    p.wearHeld();
    saves.save(game, 'slot');

    final back = (await _start(spec, save: saves.read('slot'))).player;
    expect(back.hunger, closeTo(7.5, 0.01));
    expect(back.xp, 12);
    expect(back.level, 3);
    expect(back.effects.power('swiftness'), 2.0);
    expect(back.worn['chest']?.id, 'tunic');

    final file = File('${dir.path}/slot/game.json');
    final state = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final player = state['player']! as Map<String, Object?>;
    for (final key in const ['hunger', 'xp', 'level', 'effects', 'worn']) {
      player.remove(key);
    }
    state['version'] = 1;
    file.writeAsStringSync(jsonEncode(state));
    final old = (await _start(spec, save: saves.read('slot'))).player;
    expect(old.hunger, 20.0, reason: 'a save from before hunger stands up fed');
    expect(old.level, 0);
    expect(old.worn, isEmpty);
  });

  test('a food of an undeclared effect, or armour for a slot the player lacks, is refused', () {
    final spec = _flat();
    final blocks = spec.buildBlocks();
    expect(
      () => spec.copyWith(effects: const []).buildItems(blocks),
      throwsArgumentError,
      reason: 'the potion starts regeneration',
    );
    expect(
      () => spec.copyWith(player: const PlayerSpec(armorSlots: ['head'])).buildItems(blocks),
      throwsArgumentError,
      reason: 'the tunic is worn on the chest',
    );
    expect(
      () => spec
          .copyWith(
            items: const [ItemType('stew', color: 0, food: Food(hunger: 1, leaves: 'bowl'))],
          )
          .buildItems(blocks),
      throwsArgumentError,
      reason: 'there is no bowl',
    );
    expect(spec.buildItems(blocks)['tunic'].armor!.points, 3);
  });
}
