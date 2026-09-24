import 'blocks.dart';

/// Item table. Every block is also an item (kind block, id == block id). Tools
/// carry a tool type and tier; weapons a damage; food a nutrition.
enum ItemKind { block, tool, weapon, food, material, equipment }

class ItemDef {
  const ItemDef({
    required this.id,
    required this.name,
    required this.kind,
    required this.r,
    required this.g,
    required this.b,
    this.block = -1,
    this.stack = 64,
    this.tool = ToolType.none,
    this.tier = 0,
    this.damage = 1,
    this.durability = 0,
    this.style = 'melee',
    this.hunger = 0,
    this.heal = 0.0,
    this.armor = 0,
    this.effect = '',
    this.seconds = 0.0,
    this.container = '',
    this.liquid = '',
  });

  final String id;
  final String name;
  final ItemKind kind;
  final double r, g, b;
  final int block;
  final int stack;
  final ToolType tool;
  final int tier;
  final int damage;
  final int durability;
  final String style;
  final int hunger;
  final double heal;
  final int armor;

  /// A potion's effect id, or "cure" to clear every bad effect ("" otherwise).
  final String effect;

  /// How long the potion's effect lasts.
  final double seconds;

  /// The item handed back when this one is consumed (an empty bucket).
  final String container;

  /// The block a filled bucket pours ("" for anything that is not one).
  final String liquid;
}

class Items {
  Items._();

  static const List<String> tierNames = ['Hand', 'Wooden', 'Stone', 'Iron', 'Diamond'];
  static const List<double> tierSpeed = [1.0, 2.0, 4.0, 6.0, 9.0];
  static const List<List<double>> tierColors = [
    [1, 1, 1],
    [0.70, 0.52, 0.30],
    [0.55, 0.55, 0.57],
    [0.85, 0.85, 0.88],
    [0.45, 0.90, 0.88],
  ];

  static final Map<String, ItemDef> defs = _build();

  static Map<String, ItemDef> _build() {
    final out = <String, ItemDef>{};
    void add(ItemDef d) => out[d.id] = d;
    void mat(String id, String name, double r, double g, double b) =>
        add(ItemDef(id: id, name: name, kind: ItemKind.material, r: r, g: g, b: b));
    void food(String id, String name, double r, double g, double b, int hunger, double heal) =>
        add(ItemDef(id: id, name: name, kind: ItemKind.food, r: r, g: g, b: b, stack: 16, hunger: hunger, heal: heal));
    void tool(String id, String name, List<double> c, ToolType tool, int tier, int damage) => add(ItemDef(
        id: id, name: name, kind: ItemKind.tool, r: c[0], g: c[1], b: c[2], stack: 1,
        tool: tool, tier: tier, damage: damage, durability: 60 * tier * tier));
    // A potion is food with an effect: drunk with H or the right button, no
    // hunger, no heal.
    void potion(String id, String name, double r, double g, double b, String effect, double seconds) =>
        add(ItemDef(id: id, name: name, kind: ItemKind.food, r: r, g: g, b: b, stack: 16, effect: effect, seconds: seconds));
    void weapon(String id, String name, double r, double g, double b, int damage, String style, int tier) => add(ItemDef(
        id: id, name: name, kind: ItemKind.weapon, r: r, g: g, b: b, stack: 1,
        damage: damage, style: style, tier: tier, tool: ToolType.sword, durability: 40 + 50 * tier));

    for (var i = 0; i < Blocks.count; i++) {
      if (i == Blocks.air) continue;
      final d = Blocks.def(i);
      if (d.hardness < 0 && d.id != 'bedrock') continue; // water/lava are not items
      // Orientations of one item.
      if (const [
        'door_x', 'door_z_open', 'door_x_open', 'wall_torch',
        'oak_stairs_e', 'oak_stairs_s', 'oak_stairs_w',
        'stone_stairs_e', 'stone_stairs_s', 'stone_stairs_w',
        // Stage 27: powered states and orientations of one item.
        'lever_on', 'button_on', 'wire_on', 'redstone_lamp_on', 'iron_door_x', 'iron_door_z_open', 'iron_door_x_open',
        'piston_e', 'piston_s', 'piston_w', 'piston_n_on', 'piston_e_on', 'piston_s_on', 'piston_w_on',
        // Stage 28: rail orientations and powered states.
        'rail_ew', 'rail_ne', 'rail_nw', 'rail_se', 'rail_sw', 'rail_slope_n', 'rail_slope_e', 'rail_slope_s', 'rail_slope_w',
        'powered_rail_ew', 'powered_rail_ns_on', 'powered_rail_ew_on',
      ].contains(d.id)) {
        continue;
      }
      var itemId = d.id;
      if (itemId == 'door_z') {
        itemId = 'door';
      } else if (itemId == 'iron_door_z') {
        itemId = 'iron_door';
      } else if (itemId == 'lever_off' || itemId == 'wire_off' || itemId == 'redstone_lamp_off') {
        itemId = itemId.substring(0, itemId.length - 4); // stage 27: the item is the unpowered block
      } else if (itemId == 'piston_n') {
        itemId = 'piston';
      } else if (itemId == 'rail_ns' || itemId == 'powered_rail_ns') {
        itemId = itemId.substring(0, itemId.length - 3); // stage 28: the item is the rail, the block its orientation
      } else if (itemId.endsWith('_stairs_n')) {
        itemId = itemId.substring(0, itemId.length - 2); // oak_stairs_n -> oak_stairs
      }
      add(ItemDef(id: itemId, name: d.name, kind: ItemKind.block, block: i, r: d.r, g: d.g, b: d.b));
    }
    add(const ItemDef(id: 'boat', name: 'Boat', kind: ItemKind.equipment, stack: 1, r: 0.55, g: 0.38, b: 0.20));
    // Stage 28: carts are placed on a rail (RMB) and ridden or opened with F.
    add(const ItemDef(id: 'minecart', name: 'Minecart', kind: ItemKind.equipment, stack: 1, r: 0.55, g: 0.55, b: 0.58));
    add(const ItemDef(id: 'chest_minecart', name: 'Chest Minecart', kind: ItemKind.equipment, stack: 1, r: 0.58, g: 0.44, b: 0.28));
    // Stage 20: the rod and the buckets are equipment (a tool with ToolType.none
    // would mine at wood speed).
    add(const ItemDef(id: 'fishing_rod', name: 'Fishing Rod', kind: ItemKind.equipment, stack: 1, r: 0.62, g: 0.45, b: 0.25));
    add(const ItemDef(id: 'bucket', name: 'Bucket', kind: ItemKind.equipment, stack: 1, r: 0.80, g: 0.80, b: 0.83));
    add(const ItemDef(id: 'water_bucket', name: 'Water Bucket', kind: ItemKind.equipment, stack: 1, r: 0.25, g: 0.45, b: 0.80, liquid: 'water'));
    add(const ItemDef(id: 'lava_bucket', name: 'Lava Bucket', kind: ItemKind.equipment, stack: 1, r: 0.95, g: 0.45, b: 0.12, liquid: 'lava'));
    // Stage 29: the flint and steel lights an obsidian frame into a portal.
    add(const ItemDef(id: 'flint_and_steel', name: 'Flint and Steel', kind: ItemKind.equipment, stack: 1, r: 0.70, g: 0.70, b: 0.74));

    mat('stick', 'Stick', 0.60, 0.45, 0.25);
    mat('coal', 'Coal', 0.15, 0.15, 0.16);
    mat('raw_iron', 'Raw Iron', 0.72, 0.58, 0.48);
    mat('iron_ingot', 'Iron Ingot', 0.85, 0.85, 0.88);
    mat('raw_gold', 'Raw Gold', 0.85, 0.70, 0.30);
    mat('gold_ingot', 'Gold Ingot', 0.95, 0.80, 0.25);
    mat('diamond', 'Diamond', 0.45, 0.92, 0.90);
    mat('flint', 'Flint', 0.25, 0.25, 0.28);
    mat('string', 'String', 0.90, 0.90, 0.85);
    mat('leather', 'Leather', 0.65, 0.42, 0.25);
    mat('feather', 'Feather', 0.95, 0.95, 0.95);
    mat('bone', 'Bone', 0.90, 0.88, 0.78);
    mat('slime_ball', 'Slime Ball', 0.45, 0.85, 0.40);
    mat('spider_eye', 'Spider Eye', 0.55, 0.15, 0.20);
    mat('gunpowder', 'Gunpowder', 0.35, 0.35, 0.35);
    mat('magic_dust', 'Magic Dust', 0.65, 0.40, 0.95);
    mat('redstone_dust', 'Redstone Dust', 0.85, 0.15, 0.12);
    mat('gem_shard', 'Gem Shard', 0.95, 0.35, 0.65);
    mat('wheat_seeds', 'Wheat Seeds', 0.55, 0.65, 0.30);
    mat('wheat', 'Wheat', 0.85, 0.72, 0.30);
    // Stage 29: what the underworld yields.
    mat('glowstone_dust', 'Glowstone Dust', 0.98, 0.88, 0.55);
    mat('quartz', 'Quartz', 0.92, 0.90, 0.88);
    mat('blaze_rod', 'Blaze Rod', 0.95, 0.65, 0.20);
    mat('underworld_heart', 'Underworld Heart', 0.75, 0.15, 0.55);

    food('apple', 'Apple', 0.85, 0.20, 0.20, 3, 2.0);
    food('raw_beef', 'Raw Beef', 0.75, 0.30, 0.30, 2, 0.0);
    food('cooked_beef', 'Steak', 0.50, 0.28, 0.18, 6, 6.0);
    food('raw_pork', 'Raw Pork', 0.90, 0.60, 0.65, 2, 0.0);
    food('cooked_pork', 'Cooked Pork', 0.70, 0.45, 0.30, 6, 6.0);
    food('raw_mutton', 'Raw Mutton', 0.80, 0.40, 0.40, 2, 0.0);
    food('cooked_mutton', 'Cooked Mutton', 0.60, 0.35, 0.25, 5, 5.0);
    food('raw_chicken', 'Raw Chicken', 0.90, 0.75, 0.70, 2, 0.0);
    food('cooked_chicken', 'Cooked Chicken', 0.75, 0.55, 0.35, 5, 5.0);
    food('bread', 'Bread', 0.80, 0.60, 0.30, 5, 4.0);
    food('rotten_flesh', 'Rotten Flesh', 0.45, 0.35, 0.25, 1, -2.0);
    food('mushroom_stew', 'Mushroom Stew', 0.75, 0.55, 0.40, 6, 8.0);
    food('raw_fish', 'Raw Fish', 0.60, 0.70, 0.75, 2, 0.0);
    food('cooked_fish', 'Cooked Fish', 0.80, 0.65, 0.45, 5, 5.0);
    food('raw_salmon', 'Raw Salmon', 0.90, 0.45, 0.40, 3, 0.0);
    food('cooked_salmon', 'Cooked Salmon', 0.85, 0.50, 0.35, 6, 6.0);
    food('melon_slice', 'Melon Slice', 0.90, 0.35, 0.40, 2, 1.0); // stage 26: a jungle melon gives 3-5
    // Milk: a bucket of it heals a little and cures every bad effect; the
    // bucket comes back.
    add(const ItemDef(id: 'milk_bucket', name: 'Milk Bucket', kind: ItemKind.food, stack: 1,
        r: 0.96, g: 0.96, b: 0.94, heal: 2.0, effect: 'cure', container: 'bucket'));
    food('health_potion', 'Health Potion', 0.95, 0.20, 0.35, 0, 30.0);
    mat('glass_bottle', 'Glass Bottle', 0.80, 0.90, 0.95);
    potion('speed_potion', 'Swiftness Potion', 0.45, 0.85, 0.95, 'speed', 60.0);
    potion('regen_potion', 'Regeneration Potion', 0.95, 0.40, 0.60, 'regen', 30.0);
    potion('strength_potion', 'Strength Potion', 0.90, 0.30, 0.25, 'strength', 60.0);
    potion('resistance_potion', 'Resistance Potion', 0.70, 0.70, 0.75, 'resistance', 60.0);
    potion('haste_potion', 'Haste Potion', 0.95, 0.85, 0.35, 'haste', 60.0);
    potion('antidote', 'Antidote', 0.60, 0.90, 0.60, 'cure', 0.0);

    for (var tier = 1; tier < 5; tier++) {
      final t = tierNames[tier].toLowerCase();
      final c = tierColors[tier];
      tool('${t}_pickaxe', '${tierNames[tier]} Pickaxe', c, ToolType.pickaxe, tier, 2 + tier);
      tool('${t}_axe', '${tierNames[tier]} Axe', c, ToolType.axe, tier, 3 + tier);
      tool('${t}_shovel', '${tierNames[tier]} Shovel', c, ToolType.shovel, tier, 1 + tier);
      weapon('${t}_sword', '${tierNames[tier]} Sword', c[0], c[1], c[2], 4 + tier * 2, 'melee', tier);
    }
    weapon('dagger', 'Dagger', 0.80, 0.80, 0.85, 4, 'melee_fast', 2);
    weapon('iron_dagger', 'Iron Daggers', 0.85, 0.85, 0.90, 6, 'melee_fast', 3);
    weapon('bow', 'Bow', 0.60, 0.42, 0.22, 6, 'bow', 1);
    weapon('longbow', 'Longbow', 0.50, 0.32, 0.15, 10, 'bow', 3);
    weapon('staff', 'Apprentice Staff', 0.55, 0.35, 0.75, 7, 'staff', 1);
    weapon('crystal_staff', 'Crystal Staff', 0.65, 0.45, 0.95, 12, 'staff', 3);
    // Stage 23: the Mummy King's guaranteed drop, also 10% of a temple chest.
    weapon('ancient_blade', 'Ancient Blade', 0.80, 0.70, 0.35, 14, 'melee', 4);
    tool('wooden_hoe', 'Wooden Hoe', tierColors[1], ToolType.hoe, 1, 1);
    tool('shears', 'Shears', const [0.78, 0.78, 0.82], ToolType.shears, 3, 1);
    add(const ItemDef(id: 'arrow', name: 'Arrow', kind: ItemKind.material, r: 0.75, g: 0.70, b: 0.60));
    add(const ItemDef(id: 'glider', name: 'Hang Glider', kind: ItemKind.equipment, stack: 1, r: 0.90, g: 0.35, b: 0.25));
    add(const ItemDef(id: 'leather_armor', name: 'Leather Armor', kind: ItemKind.equipment, stack: 1, r: 0.65, g: 0.42, b: 0.25, armor: 2));
    add(const ItemDef(id: 'iron_armor', name: 'Iron Armor', kind: ItemKind.equipment, stack: 1, r: 0.85, g: 0.85, b: 0.88, armor: 5));
    add(const ItemDef(id: 'diamond_armor', name: 'Diamond Armor', kind: ItemKind.equipment, stack: 1, r: 0.45, g: 0.90, b: 0.88, armor: 8));
    return out;
  }

  static bool has(String id) => defs.containsKey(id);

  static ItemDef def(String id) {
    final d = defs[id];
    if (d == null) throw ArgumentError('unknown item: $id');
    return d;
  }

  static String displayName(String id) => def(id).name;
  static int stackSize(String id) => def(id).stack;
  static ItemKind kind(String id) => def(id).kind;
  static int blockOf(String id) => def(id).block;
  static bool isBlock(String id) => def(id).kind == ItemKind.block;
  static ToolType toolOf(String id) => def(id).tool;
  static int tierOf(String id) => def(id).tier;
  static int damageOf(String id) => def(id).damage;
  static String styleOf(String id) => def(id).style;

  /// Stage 23: swings, shots and broken blocks a tool or weapon survives; 0 for
  /// anything that never wears. The live count sits on the inventory slot
  /// (`ItemStack.dur`), this is the maximum.
  static int durabilityOf(String id) => def(id).durability;

  /// The block a filled bucket pours ("" for anything that is not one).
  static String liquidOf(String id) => def(id).liquid;

  static bool isLeaves(int block) => Blocks.idOf(block).endsWith('_leaves');

  /// Time in seconds to break `block` holding `itemId` ("" for the bare hand).
  /// -1 = never.
  static double mineTime(String itemId, int block) {
    final hardness = Blocks.hardness(block);
    if (hardness < 0.0) return -1.0;
    if (hardness == 0.0) return 0.05;
    if (itemId != '' && toolOf(itemId) == ToolType.shears && isLeaves(block)) return 0.05;
    final neededTool = Blocks.toolOf(block);
    final neededTier = Blocks.minTier(block);
    final tool = itemId == '' ? ToolType.none : toolOf(itemId);
    final tier = itemId == '' ? 0 : tierOf(itemId);
    if (neededTool != ToolType.none && (tool != neededTool || tier < neededTier)) {
      if (neededTier > 0 && tier < neededTier) {
        return (tool == neededTool || neededTier > 0) ? -1.0 : hardness * 3.0;
      }
      return hardness * 3.0;
    }
    final speed = tool == neededTool ? tierSpeed[tier] : 1.0;
    return hardness / speed;
  }
}
