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
