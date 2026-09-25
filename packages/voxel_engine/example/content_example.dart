// A game's content in one file: blocks and items by id, mining times, an
// inventory, crafting, a loot roll and a status effect.
//
//   dart run example/content_example.dart
import 'dart:math' as math;

import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';

/// The blocks, air first. Their order numbers them for the engine.
final BlockRegistry<BlockType> blocks = BlockRegistry(const [
  BlockType('air', color: 0, solid: false, hardness: -1, drop: ''),
  BlockType('stone', color: 0x7F7F84, hardness: 1.5, tool: 'pickaxe', tier: 1, drop: 'cobblestone'),
  BlockType('cobblestone', color: 0x6E6E70, hardness: 2.0, tool: 'pickaxe'),
  BlockType('dirt', color: 0x8A5E3B, hardness: 0.5, tool: 'shovel', tags: {'earth'}),
  BlockType('log', color: 0x6B4F2A, hardness: 2.0, tool: 'axe'),
  BlockType('planks', color: 0xB08850, hardness: 2.0, tool: 'axe'),
  BlockType('torch', color: 0xFFD070, shape: BlockShape.torch, solid: false, hardness: 0, light: 14),
  BlockType.liquid('water', color: 0x3366CC),
]);

/// Every block you can hold, plus the items that are not blocks.
final ItemRegistry<ItemType> items = ItemRegistry([
  ...ItemRegistry.forBlocks(blocks),
  const ItemType('coal', color: 0x202020),
  const ItemType('wooden_pickaxe', color: 0xB08850, tool: 'pickaxe', tier: 1, stack: 1, durability: 60, damage: 2),
]);

void main() {
  // 1. Blocks: an id for you, a number for the engine.
  final stone = blocks.indexOf('stone');
  print(
    'stone is block $stone, drops ${blocks.dropOf(stone)}; '
    'the torch gives light ${blocks.table.emissionOf(blocks.indexOf('torch'))}',
  );

  // 2. Mining: the right tool is fast, the hand cannot break stone.
  const rules = MiningRules();
  print(
    'stone by hand: ${rules.mineTime(blocks[stone], null)} (-1: cannot), '
    'with a wooden pickaxe: ${rules.mineTime(blocks[stone], items['wooden_pickaxe'])} s',
  );

  // 3. An inventory that knows stack sizes and tool wear.
  final bag = Inventory(stackSize: (id) => items[id].stack, maxDurability: (id) => items[id].durability)
    ..add('log', 3)
    ..add('coal', 1)
    ..add('wooden_pickaxe', 1);
  bag.wear(bag.find('wooden_pickaxe'), 10);
  print('the bag holds ${bag.countOf('log')} logs; the pickaxe has ${bag.durAt(bag.find('wooden_pickaxe'))} uses left');

  // 4. Crafting takes everything or nothing.
  final book = RecipeBook(const [
    Recipe('planks', 4, {'log': 1}),
    Recipe('torch', 4, {'coal': 1, 'planks': 1}),
  ]);
  for (final r in book.available('')) {
    book.craft(r, bag);
  }
  print('after crafting: ${bag.countOf('planks')} planks, ${bag.countOf('torch')} torches, ${bag.countOf('log')} logs');

  // 5. Loot: the same chest rolls the same loot on every machine.
  const chest = LootTable([LootEntry('coal', 1, 4, 1.0), LootEntry('wooden_pickaxe', 1, 1, 0.25)]);
  final loot = chest.roll(math.Random(LootTable.seedFor(const IVec3(10, 64, -3), 2024)));
  print('the chest at (10, 64, -3) holds ${[for (final l in loot) '${l.count} ${l.id}']}');

  // 6. Status effects tick, bend stats and wear off.
  final effects =
      StatusEffects(const {
          'poison': EffectType('poison', 'Poisoned', 0.3, 0.8, 0.3, period: 1, damage: 1, bad: true),
          'speed': EffectType('speed', 'Swiftness', 0.4, 0.8, 0.9, stats: {'speed': StatModifier.multiply(0.3)}),
        })
        ..apply('poison', 3)
        ..apply('speed', 10);
  var hurt = 0.0;
  for (var t = 0; t < 5; t++) {
    for (final e in effects.tick(1.0)) {
      hurt += e.damage;
    }
  }
  print(
    'poison dealt $hurt damage and wore off: ${!effects.has('poison')}; '
    'speed is x${effects.multiplier('speed')} for ${effects.timeLeft('speed')} s more',
  );

  // 7. Everything saves as JSON.
  final back = Inventory(stackSize: (id) => items[id].stack)..fromJson(bag.toJson(), known: items.has);
  print('the bag saved and loaded: ${back.countOf('torch')} torches');
}
