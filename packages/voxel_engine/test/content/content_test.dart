import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/content.dart';

final BlockRegistry<BlockType> blocks = BlockRegistry(const [
  BlockType('air', color: 0, solid: false, hardness: -1, drop: ''),
  BlockType('stone', color: 0x808080, hardness: 3, tool: 'pickaxe', tier: 1, drop: 'cobblestone'),
  BlockType('dirt', color: 0x8B5A2B, hardness: 0.8, tool: 'shovel', tags: {'earth'}),
  BlockType('glass', color: 0xCCEEFF, alpha: 0.3, hardness: 0.3),
  BlockType.liquid('water', color: 0x3366CC),
  BlockType.liquid('water_flow', color: 0x3366CC, kind: 'water', source: false),
  BlockType('flower', color: 0xFF3030, shape: BlockShape.flower, solid: false, hardness: 0, tags: {'plant'}),
  BlockType('soul_sand', color: 0x503828, speed: 0.5, tags: {'earth'}),
  BlockType.liquid('lava', color: 0xFF6010, light: 15),
]);

final ItemRegistry<ItemType> items = ItemRegistry([
  ...ItemRegistry.forBlocks(blocks),
  const ItemType('cobblestone', color: 0x707070),
  const ItemType('wooden_pickaxe', color: 0xB08850, tool: 'pickaxe', tier: 1, stack: 1, durability: 60),
  const ItemType('stone_shovel', color: 0x8C8C90, tool: 'shovel', tier: 2, stack: 1),
]);

void main() {
  group('BlockRegistry', () {
    test('numbers blocks in order and projects the engine table', () {
      expect(blocks.count, 9);
      expect(blocks.indexOf('stone'), 1);
      expect(blocks.idOf(4), 'water');
      expect(() => blocks.indexOf('cheese'), throwsArgumentError);
      final t = blocks.table;
      expect(t.isSolid(blocks.indexOf('stone')), isTrue);
      expect(t.isOpaque(blocks.indexOf('glass')), isFalse, reason: 'translucent defaults to not opaque');
      expect(t.isLiquid(blocks.indexOf('water_flow')), isTrue);
      expect(t.isLiquidSource(blocks.indexOf('water_flow')), isFalse);
      expect(t.emissionOf(blocks.indexOf('lava')), 15);
      expect(blocks.liquidKinds, ['water', 'lava']);
      expect(t.liquidKind(blocks.indexOf('lava')), 1);
      expect(blocks.flowingOf('water'), blocks.indexOf('water_flow'));
      expect(() => blocks.flowingOf('lava'), throwsStateError);
    });

    test('names, drops, tags, replaceable, path costs', () {
      expect(blocks[blocks.indexOf('soul_sand')].name, 'Soul Sand');
      expect(blocks.dropOf(blocks.indexOf('stone')), 'cobblestone');
      expect(blocks.dropOf(blocks.indexOf('dirt')), 'dirt');
      expect(blocks.dropOf(0), '');
      expect(blocks.withTag('earth'), [2, 7]);
      expect(blocks.isReplaceable(blocks.indexOf('flower')), isTrue);
      expect(blocks.isReplaceable(blocks.indexOf('dirt')), isFalse);
      final costs = blocks.pathCosts(avoidLiquids: {'lava'});
      expect(costs.avoid(blocks.indexOf('lava')), isTrue);
      expect(costs.avoid(blocks.indexOf('water')), isFalse);
      expect(costs.floorCost(blocks.indexOf('soul_sand')), 2.0);
      expect(blocks.ids['glass'], 3);
    });

    test('refuses a registry that does not start with air, or repeats an id', () {
      expect(() => BlockRegistry(const [BlockType('stone', color: 0)]), throwsArgumentError);
      expect(
        () => BlockRegistry(const [
          BlockType('air', color: 0, solid: false),
          BlockType('a', color: 0),
          BlockType('a', color: 0),
        ]),
        throwsArgumentError,
      );
    });

    test('refuses a block that leans on, or turns into, a block that does not exist', () {
      const air = BlockType('air', color: 0, solid: false);
      expect(
        () => BlockRegistry(const [
          air,
          BlockType('torch', color: 0, solid: false, onWall: 'wall_torch'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => BlockRegistry(const [
          air,
          BlockType('wheat', color: 0, solid: false, support: Support.below(on: {'farmland'})),
        ]),
        throwsArgumentError,
      );
    });

    test('a facing picks the variant the placer looks toward, or along', () {
      const stairs = Facing.compass(north: 'n', east: 'e', south: 's', west: 'w');
      expect(stairs.toward(0, -1), 'n', reason: 'north is -Z');
      expect(stairs.toward(0.9, 0.2), 'e');
      expect(stairs.toward(-0.1, 0.8), 's');
      expect(stairs.toward(-0.7, -0.3), 'w');
      const door = Facing.axis(x: 'door_x', z: 'door_z');
      expect(door.toward(-0.9, 0.1), 'door_x');
      expect(door.toward(0.1, 0.9), 'door_z');
      expect(stairs.variants, ['n', 'e', 's', 'w']);
      expect(door.variants, ['door_x', 'door_z']);
      expect(
        () => BlockRegistry(const [
          BlockType('air', color: 0, solid: false),
          BlockType('door_z', color: 0, facing: door),
        ]),
        throwsArgumentError,
        reason: 'door_x does not exist',
      );
      expect(
        () => BlockRegistry(const [
          BlockType('air', color: 0, solid: false),
          BlockType('wheat_0', color: 0, grows: Growth('wheat_1', seconds: 30)),
        ]),
        throwsArgumentError,
        reason: 'wheat_1 does not exist',
      );
      expect(
        () => BlockRegistry(const [
          BlockType('air', color: 0, solid: false),
          BlockType('dirt', color: 0, turnsWith: {'hoe': 'farmland'}),
        ]),
        throwsArgumentError,
        reason: 'farmland does not exist',
      );
    });

    test('a block stands where what it leans on is', () {
      final r = BlockRegistry(const [
        BlockType('air', color: 0, solid: false),
        BlockType('stone', color: 0x808080),
        BlockType('glass', color: 0xCCEEFF, alpha: 0.3),
        BlockType('farmland', color: 0x664422),
        BlockType('torch', color: 0xFFD070, solid: false, support: Support.below()),
        BlockType('ladder', color: 0x996633, solid: false, support: Support.side()),
        BlockType('wheat', color: 0x99BB44, solid: false, support: Support.below(on: {'farmland'})),
      ]);
      final w = _Cells(r.table);
      const at = IVec3(0, 5, 0);
      int id(String name) => r.indexOf(name);
      expect(r.stands(w, at, id('stone')), isTrue, reason: 'a block with no support stands anywhere');
      expect(r.stands(w, at, id('torch')), isFalse);
      w.cells[at + IVec3.down] = id('glass');
      expect(r.stands(w, at, id('torch')), isTrue, reason: 'any solid block below will do');
      expect(r.stands(w, at, id('wheat')), isFalse, reason: 'wheat stands on farmland only');
      w.cells[at + IVec3.down] = id('farmland');
      expect(r.stands(w, at, id('wheat')), isTrue);
      expect(r.stands(w, at, id('ladder')), isFalse, reason: 'the floor is not a wall');
      w.cells[at + IVec3.right] = id('glass');
      expect(r.stands(w, at, id('ladder')), isFalse, reason: 'a wall must be opaque');
      w.cells[at + IVec3.back] = id('stone');
      expect(r.stands(w, at, id('ladder')), isTrue);
    });
  });

  group('items and mining', () {
    const rules = MiningRules();
    BlockType b(String id) => blocks[blocks.indexOf(id)];

    test('every holdable block is an item', () {
      expect(items.has('stone'), isTrue);
      expect(items['dirt'].block, 'dirt');
      expect(items.has('water'), isFalse);
      expect(items.has('air'), isFalse);
    });

    test('the right tool at its tier is fast, the hand is slow, a missing tier cannot', () {
      expect(rules.mineTime(b('dirt'), null), closeTo(0.8 * 3, 1e-9), reason: 'no shovel: three times the hardness');
      expect(rules.mineTime(b('dirt'), items['stone_shovel']), closeTo(0.8 / 4, 1e-9));
      expect(rules.mineTime(b('stone'), null), -1, reason: 'stone asks for a tier-1 pickaxe');
      expect(rules.mineTime(b('stone'), items['wooden_pickaxe']), closeTo(3 / 2, 1e-9));
      expect(rules.mineTime(b('flower'), null), 0.05);
      expect(rules.mineTime(b('water'), items['wooden_pickaxe']), -1);
      expect(rules.drops(b('stone'), items['wooden_pickaxe']), isTrue);
      expect(rules.drops(b('stone'), items['stone_shovel']), isFalse);
    });

    test('an item says what eating it does and where it is worn', () {
      const stew = ItemType('stew', color: 0x8B5A2B, stack: 1, food: Food(hunger: 6, heal: 2.0, leaves: 'bowl'));
      const potion = ItemType('potion', color: 0xFF30A0, food: Food(effect: 'regeneration', seconds: 10.0, power: 2.0));
      const helmet = ItemType('helmet', color: 0xC0C0C0, stack: 1, armor: Armor('head', 2));
      expect(stew.food!.hunger, 6);
      expect(stew.food!.leaves, 'bowl');
      expect(stew.armor, isNull);
      expect(potion.food!.effect, 'regeneration');
      expect(potion.food!.hunger, 0, reason: 'a drink fills nothing');
      expect(helmet.armor!.slot, 'head');
      expect(helmet.food, isNull);
      expect(items['stone'].food, isNull, reason: "a block's item is neither eaten nor worn");
    });

    test('an effect without its seconds, or seconds without an effect, is refused', () {
      // ignore: prefer_const_constructors
      expect(() => Food(effect: 'regeneration'), throwsA(isA<AssertionError>()));
      // ignore: prefer_const_constructors
      expect(() => Food(hunger: 2, seconds: 5.0), throwsA(isA<AssertionError>()));
      // ignore: prefer_const_constructors
      expect(() => Armor('chest', 0), throwsA(isA<AssertionError>()));
    });
  });

  group('Inventory', () {
    Inventory inv() => Inventory(stackSize: (id) => items[id].stack, maxDurability: (id) => items[id].durability);

    test('tops up stacks, then opens slots, and says what did not fit', () {
      final i = inv();
      expect(i.add('dirt', 100), 0);
      expect(i.countAt(0), 64);
      expect(i.countAt(1), 36);
      expect(i.add('dirt', 30), 0);
      expect(i.countAt(1), 64);
      expect(i.countAt(2), 2);
      final full = Inventory(stackSize: (id) => 64, capacity: 2);
      expect(full.add('dirt', 200), 72);
      expect(full.roomFor('dirt', 10), 0);
    });

    test('remove takes from the back and all-or-nothing; wear breaks a tool', () {
      final i = inv()..add('dirt', 70);
      expect(i.remove('dirt', 100), isFalse);
      expect(i.countOf('dirt'), 70);
      expect(i.remove('dirt', 10), isTrue);
      expect(i.countAt(1), 0);
      expect(i.countAt(0), 60);
      i.add('wooden_pickaxe', 1);
      final slot = i.find('wooden_pickaxe');
      expect(i.durAt(slot), 60);
      expect(i.wear(slot, 59), isFalse);
      expect(i.durAt(slot), 1);
      expect(i.wear(slot), isTrue);
      expect(i.isEmptySlot(slot), isTrue);
    });

    test('round-trips through JSON, dropping unknown items', () {
      final i = inv()
        ..add('dirt', 5)
        ..addStack(ItemStack('wooden_pickaxe', 1, bonus: 2, dur: 7))
        ..addStack(ItemStack('ghost_item', 1));
      final back = inv()..fromJson(i.toJson(), known: items.has);
      expect(back.countOf('dirt'), 5);
      expect(back.slots[1]!.bonus, 2);
      expect(back.slots[1]!.dur, 7);
      expect(back.countOf('ghost_item'), 0);
      var calls = 0;
      back.listeners.add(() => calls++);
      back.swap(0, 1);
      expect(calls, 1);
      expect(back.idAt(0), 'wooden_pickaxe');
    });
  });

  test('RecipeBook crafts all-or-nothing, by station', () {
    final book = RecipeBook(const [
      Recipe('glass', 1, {'dirt': 2}),
      Recipe('stone', 1, {'cobblestone': 1}, station: 'furnace'),
    ]);
    expect(book.available(''), hasLength(1));
    expect(book.available('furnace'), hasLength(2));
    final i = Inventory(stackSize: (id) => 64)..add('dirt', 3);
    expect(book.craft(book.recipes[0], i), isTrue);
    expect(i.countOf('dirt'), 1);
    expect(i.countOf('glass'), 1);
    expect(book.craft(book.recipes[0], i), isFalse);
    expect(i.countOf('dirt'), 1);
  });

  test('LootTable rolls each row once, seeded the same everywhere', () {
    const table = LootTable([LootEntry('gold', 2, 4, 1.0), LootEntry('never', 1, 1, 0.0)]);
    final seed = LootTable.seedFor(const IVec3(10, 64, -3), 42);
    expect(seed, LootTable.seedFor(const IVec3(10, 64, -3), 42));
    final a = table.roll(math.Random(seed)), b = table.roll(math.Random(seed));
    expect(a, b);
    expect(a.single.id, 'gold');
    expect(a.single.count, inInclusiveRange(2, 4));
  });

  group('StatusEffects', () {
    const types = {
      'poison': EffectType('poison', 'Poisoned', 0.3, 0.8, 0.3, period: 2, damage: 1, bad: true),
      'speed': EffectType('speed', 'Swiftness', 0.4, 0.8, 0.9, stats: {'speed': StatModifier.multiply(0.3)}),
      'slow': EffectType('slow', 'Slowed', 0.5, 0.6, 0.8, bad: true, stats: {'speed': StatModifier.divide(0.4)}),
      'resistance': EffectType('resistance', 'Resistance', 0.7, 0.7, 0.7, stats: {'armor': StatModifier.add(4)}),
    };

    test('ticks by period, times power, and expires', () {
      final e = StatusEffects(types)..apply('poison', 5, 2);
      expect(e.tick(1.0), isEmpty);
      final ev = e.tick(1.0);
      expect(ev.single.damage, 2.0);
      e.tick(3.1);
      expect(e.has('poison'), isFalse);
    });

    test('stats bend by modifiers; a cure clears only the bad', () {
      final e = StatusEffects(types)
        ..apply('speed', 10)
        ..apply('slow', 10, 2)
        ..apply('resistance', 10, 1.5);
      expect(e.multiplier('speed'), closeTo(1.3 / 1.8, 1e-12));
      expect(e.bonus('armor'), 6.0);
      expect(e.multiplier('damage'), 1.0);
      expect(e.clearBad(), 1);
      expect(e.multiplier('speed'), closeTo(1.3, 1e-12));
      final back = StatusEffects(types)..fromJson(e.toJson());
      expect(back.timeLeft('speed'), 10);
      expect(() => e.apply('nope', 1), throwsArgumentError);
    });
  });
}

/// A few cells by hand, air everywhere else.
class _Cells implements VoxelQuery {
  _Cells(this.table);

  @override
  final VoxelBlockTable table;

  final Map<IVec3, int> cells = {};

  @override
  int getBlockXYZ(int x, int y, int z) => cells[IVec3(x, y, z)] ?? 0;
}
