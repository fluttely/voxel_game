import 'package:voxel_engine/content.dart' show Recipe, RecipeBook;

import '../game/inventory.dart';

export 'package:voxel_engine/content.dart' show Recipe;

/// Recipe list. station: "" by hand, "crafting_table", "furnace",
/// "brewing_stand". VK3.3: voxel_content's [Recipe] rows in a [RecipeBook].

class Recipes {
  Recipes._();

  static final RecipeBook book = RecipeBook(_build());

  static List<Recipe> get list => book.recipes;

  static List<Recipe> _build() {
    final out = <Recipe>[];
    void r(String result, int count, Map<String, int> ingredients, [String station = '']) {
      final clean = <String, int>{
        for (final e in ingredients.entries)
          if (e.value > 0) e.key: e.value,
      };
      out.add(Recipe(result, count, clean, station: station));
    }

    r('oak_planks', 4, {'oak_log': 1});
    r('spruce_planks', 4, {'spruce_log': 1});
    r('stick', 4, {'oak_planks': 2});
    r('stick', 4, {'spruce_planks': 2});
    r('crafting_table', 1, {'oak_planks': 4});
    r('crafting_table', 1, {'spruce_planks': 4});
    r('torch', 4, {'coal': 1, 'stick': 1});
    r('wooden_pickaxe', 1, {'oak_planks': 3, 'stick': 2});
    r('wooden_axe', 1, {'oak_planks': 3, 'stick': 2});
    r('wooden_shovel', 1, {'oak_planks': 1, 'stick': 2});
    r('wooden_sword', 1, {'oak_planks': 2, 'stick': 1});
    r('ladder', 3, {'stick': 7});
    r('oak_slab', 6, {'oak_planks': 3});
    r('stone_slab', 6, {'stone': 3});
    r('cobblestone_slab', 6, {'cobblestone': 3});
    r('mushroom_stew', 1, {'mushroom': 2, 'wooden_shovel': 0});
    // Stage 27: redstone-lite
    r('lever', 1, {'stick': 1, 'cobblestone': 1});
    r('button', 1, {'stone': 1});
    r('wire', 4, {'redstone_dust': 1});
    // Table
    r('stone_pickaxe', 1, {'cobblestone': 3, 'stick': 2}, 'crafting_table');
    r('stone_axe', 1, {'cobblestone': 3, 'stick': 2}, 'crafting_table');
    r('stone_shovel', 1, {'cobblestone': 1, 'stick': 2}, 'crafting_table');
    r('stone_sword', 1, {'cobblestone': 2, 'stick': 1}, 'crafting_table');
    r('iron_pickaxe', 1, {'iron_ingot': 3, 'stick': 2}, 'crafting_table');
    r('iron_axe', 1, {'iron_ingot': 3, 'stick': 2}, 'crafting_table');
    r('iron_shovel', 1, {'iron_ingot': 1, 'stick': 2}, 'crafting_table');
    r('iron_sword', 1, {'iron_ingot': 2, 'stick': 1}, 'crafting_table');
    r('diamond_pickaxe', 1, {'diamond': 3, 'stick': 2}, 'crafting_table');
    r('diamond_axe', 1, {'diamond': 3, 'stick': 2}, 'crafting_table');
    r('diamond_shovel', 1, {'diamond': 1, 'stick': 2}, 'crafting_table');
    r('diamond_sword', 1, {'diamond': 2, 'stick': 1}, 'crafting_table');
    r('dagger', 1, {'cobblestone': 1, 'stick': 1}, 'crafting_table');
    r('iron_dagger', 1, {'iron_ingot': 2, 'stick': 1}, 'crafting_table');
    r('bow', 1, {'stick': 3, 'string': 3}, 'crafting_table');
    r('longbow', 1, {'stick': 3, 'string': 3, 'iron_ingot': 1}, 'crafting_table');
    r('arrow', 6, {'flint': 1, 'stick': 1, 'feather': 1}, 'crafting_table');
    r('staff', 1, {'stick': 2, 'magic_dust': 1}, 'crafting_table');
    r('crystal_staff', 1, {'stick': 2, 'diamond': 1, 'magic_dust': 3}, 'crafting_table');
    r('furnace', 1, {'cobblestone': 8}, 'crafting_table');
    r('chest', 1, {'oak_planks': 8}, 'crafting_table');
    r('glider', 1, {'wool': 6, 'stick': 4, 'string': 2}, 'crafting_table');
    r('leather_armor', 1, {'leather': 8}, 'crafting_table');
    r('iron_armor', 1, {'iron_ingot': 12}, 'crafting_table');
    r('diamond_armor', 1, {'diamond': 12}, 'crafting_table');
    r('lamp', 1, {'glass': 1, 'coal': 2, 'magic_dust': 1}, 'crafting_table');
    r('stone_bricks', 4, {'stone': 4}, 'crafting_table');
    r('bricks', 4, {'clay': 4}, 'furnace');
    r('wool', 1, {'string': 4}, 'crafting_table');
    r('bone_block', 1, {'bone': 9}, 'crafting_table');
    r('iron_block', 1, {'iron_ingot': 9}, 'crafting_table');
    r('gold_block', 1, {'gold_ingot': 9}, 'crafting_table');
    r('diamond_block', 1, {'diamond': 9}, 'crafting_table');
    r('bread', 1, {'wheat': 3});
    r('tnt', 1, {'gunpowder': 5, 'sand': 4}, 'crafting_table');
    r('bed', 1, {'wool': 3, 'oak_planks': 3}, 'crafting_table');
    r('door', 1, {'oak_planks': 6}, 'crafting_table');
    r('iron_door', 1, {'iron_ingot': 6}, 'crafting_table');
    r('redstone_lamp', 1, {'redstone_dust': 4, 'torch': 1}, 'crafting_table');
    r('piston', 1, {'oak_planks': 3, 'cobblestone': 4, 'iron_ingot': 1, 'redstone_dust': 1}, 'crafting_table');
    r('oak_fence', 3, {'stick': 4, 'oak_planks': 2}, 'crafting_table');
    r('oak_stairs', 4, {'oak_planks': 6}, 'crafting_table');
    r('stone_stairs', 4, {'stone_bricks': 6}, 'crafting_table');
    r('boat', 1, {'oak_planks': 5}, 'crafting_table');
    // Stage 28: rails and carts
    r('rail', 16, {'iron_ingot': 6, 'stick': 1}, 'crafting_table');
    r('powered_rail', 6, {'gold_ingot': 6, 'stick': 1, 'redstone_dust': 1}, 'crafting_table');
    r('minecart', 1, {'iron_ingot': 5}, 'crafting_table');
    r('chest_minecart', 1, {'minecart': 1, 'chest': 1}, 'crafting_table');
    r('enchanting_table', 1, {'diamond': 1, 'magic_dust': 4, 'stone_bricks': 4}, 'crafting_table');
    r('wooden_hoe', 1, {'oak_planks': 2, 'stick': 2});
    r('health_potion', 1, {'apple': 2, 'magic_dust': 1, 'glass': 1}, 'crafting_table');
    r('brewing_stand', 1, {'cobblestone': 3, 'glass': 1, 'magic_dust': 1}, 'crafting_table');
    r('glass_bottle', 3, {'glass': 1}, 'crafting_table');
    r('waypoint', 1, {'stone_bricks': 4, 'magic_dust': 2}, 'crafting_table');
    r('fishing_rod', 1, {'stick': 3, 'string': 2}, 'crafting_table');
    r('shears', 1, {'iron_ingot': 2}, 'crafting_table');
    r('bucket', 1, {'iron_ingot': 3}, 'crafting_table');
    r('flint_and_steel', 1, {'iron_ingot': 1, 'flint': 1}, 'crafting_table'); // stage 29
    r('glowstone', 1, {'glowstone_dust': 4}, 'crafting_table');
    // Brewing stand
    r('speed_potion', 1, {'glass_bottle': 1, 'wheat': 1, 'feather': 1}, 'brewing_stand');
    r('regen_potion', 1, {'glass_bottle': 1, 'apple': 1, 'magic_dust': 1}, 'brewing_stand');
    r('strength_potion', 1, {'glass_bottle': 1, 'spider_eye': 1, 'gunpowder': 1}, 'brewing_stand');
    r('resistance_potion', 1, {'glass_bottle': 1, 'iron_ingot': 1, 'slime_ball': 1}, 'brewing_stand');
    r('haste_potion', 1, {'glass_bottle': 1, 'coal': 2, 'gem_shard': 1}, 'brewing_stand');
    r('antidote', 1, {'glass_bottle': 1, 'mushroom': 1, 'bone': 1}, 'brewing_stand');
    r('health_potion', 1, {'glass_bottle': 1, 'apple': 1, 'magic_dust': 1}, 'brewing_stand');
    // Furnace (each needs 1 coal)
    r('iron_ingot', 1, {'raw_iron': 1, 'coal': 1}, 'furnace');
    r('gold_ingot', 1, {'raw_gold': 1, 'coal': 1}, 'furnace');
    r('glass', 1, {'sand': 1, 'coal': 1}, 'furnace');
    r('stone', 1, {'cobblestone': 1, 'coal': 1}, 'furnace');
    r('cooked_beef', 1, {'raw_beef': 1, 'coal': 1}, 'furnace');
    r('cooked_pork', 1, {'raw_pork': 1, 'coal': 1}, 'furnace');
    r('cooked_mutton', 1, {'raw_mutton': 1, 'coal': 1}, 'furnace');
    r('cooked_chicken', 1, {'raw_chicken': 1, 'coal': 1}, 'furnace');
    r('cooked_fish', 1, {'raw_fish': 1, 'coal': 1}, 'furnace');
    r('cooked_salmon', 1, {'raw_salmon': 1, 'coal': 1}, 'furnace');
    return out;
  }

  static List<Recipe> available(String station) => book.available(station);

  static bool canCraft(Recipe r, Inventory inv) => book.canCraft(r, inv);

  static bool craft(Recipe r, Inventory inv) => book.craft(r, inv);
}
