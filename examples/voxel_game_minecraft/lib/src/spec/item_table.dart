import 'package:voxel_game/voxel_game.dart';

/// The game's items beside the ones its blocks make (`blockTable`): the items
/// of blocks only the world turns (a door, stairs, a lever, a rail), tools and
/// weapons by tier, food and potions, materials, armour and what is ridden or
/// cast. An item named here with a block's id replaces that block's.
const List<ItemType> itemTable = [
  // The items whose block is one of several the world turns.
  ItemType.rgb('door', 0.62, 0.45, 0.25, block: 'door_z'),
  ItemType.rgb('iron_door', 0.80, 0.80, 0.83, block: 'iron_door_z'),
  ItemType.rgb('oak_stairs', 0.72, 0.56, 0.33, block: 'oak_stairs_n'),
  ItemType.rgb('stone_stairs', 0.50, 0.50, 0.52, block: 'stone_stairs_n'),
  ItemType.rgb('lever', 0.55, 0.55, 0.57, block: 'lever_off'),
  ItemType.rgb('wire', 0.45, 0.10, 0.10, name: 'Redstone Wire', block: 'wire_off'),
  ItemType.rgb('redstone_lamp', 0.45, 0.32, 0.22, block: 'redstone_lamp_off'),
  ItemType.rgb('piston', 0.62, 0.50, 0.34, block: 'piston_n'),
  ItemType.rgb('rail', 0.60, 0.60, 0.64, block: 'rail_ns'),
  ItemType.rgb('powered_rail', 0.70, 0.58, 0.28, block: 'powered_rail_ns'),
  // Seeds plant wheat on farmland.
  ItemType.rgb('wheat_seeds', 0.55, 0.65, 0.30, block: 'wheat_0'),
  // Ridden, cast, poured, lit and glided.
  ItemType.rgb('boat', 0.55, 0.38, 0.20, stack: 1),
  ItemType.rgb('minecart', 0.55, 0.55, 0.58, stack: 1),
  ItemType.rgb('fishing_rod', 0.62, 0.45, 0.25, stack: 1),
  ItemType.rgb(
    'bucket',
    0.80,
    0.80,
    0.83,
    stack: 1,
    bucket: Bucket.empty({'water': 'water_bucket', 'lava': 'lava_bucket'}),
  ),
  ItemType.rgb('water_bucket', 0.25, 0.45, 0.80, stack: 1, bucket: Bucket.full('water', empties: 'bucket')),
  ItemType.rgb('lava_bucket', 0.95, 0.45, 0.12, stack: 1, bucket: Bucket.full('lava', empties: 'bucket')),
  ItemType.rgb('flint_and_steel', 0.70, 0.70, 0.74, name: 'Flint and Steel', stack: 1),
  ItemType.rgb('glider', 0.90, 0.35, 0.25, name: 'Hang Glider', stack: 1, glider: Glider()),
  // Materials.
  ItemType.rgb('stick', 0.60, 0.45, 0.25),
  ItemType.rgb('coal', 0.15, 0.15, 0.16),
  ItemType.rgb('raw_iron', 0.72, 0.58, 0.48),
  ItemType.rgb('iron_ingot', 0.85, 0.85, 0.88),
  ItemType.rgb('raw_gold', 0.85, 0.70, 0.30),
  ItemType.rgb('gold_ingot', 0.95, 0.80, 0.25),
  ItemType.rgb('diamond', 0.45, 0.92, 0.90),
  ItemType.rgb('flint', 0.25, 0.25, 0.28),
  ItemType.rgb('string', 0.90, 0.90, 0.85),
  ItemType.rgb('leather', 0.65, 0.42, 0.25),
  ItemType.rgb('feather', 0.95, 0.95, 0.95),
  ItemType.rgb('bone', 0.90, 0.88, 0.78),
  ItemType.rgb('slime_ball', 0.45, 0.85, 0.40),
  ItemType.rgb('spider_eye', 0.55, 0.15, 0.20),
  ItemType.rgb('gunpowder', 0.35, 0.35, 0.35),
  ItemType.rgb('magic_dust', 0.65, 0.40, 0.95),
  ItemType.rgb('redstone_dust', 0.85, 0.15, 0.12),
  ItemType.rgb('gem_shard', 0.95, 0.35, 0.65),
  ItemType.rgb('wheat', 0.85, 0.72, 0.30),
  ItemType.rgb('glowstone_dust', 0.98, 0.88, 0.55),
  ItemType.rgb('quartz', 0.92, 0.90, 0.88),
  ItemType.rgb('blaze_rod', 0.95, 0.65, 0.20),
  ItemType.rgb('underworld_heart', 0.75, 0.15, 0.55),
  ItemType.rgb('glass_bottle', 0.80, 0.90, 0.95),
  ItemType.rgb('arrow', 0.75, 0.70, 0.60),
  // Food: what fills five hunger or more leaves the eater well fed for 20 s. Rotten flesh poisons a little.
  ItemType.rgb('apple', 0.85, 0.20, 0.20, stack: 16, food: Food(hunger: 3, heal: 2.0)),
  ItemType.rgb('raw_beef', 0.75, 0.30, 0.30, stack: 16, food: Food(hunger: 2)),
  ItemType.rgb('cooked_beef', 0.50, 0.28, 0.18, name: 'Steak', stack: 16, food: _wellFed6),
  ItemType.rgb('raw_pork', 0.90, 0.60, 0.65, stack: 16, food: Food(hunger: 2)),
  ItemType.rgb('cooked_pork', 0.70, 0.45, 0.30, stack: 16, food: _wellFed6),
  ItemType.rgb('raw_mutton', 0.80, 0.40, 0.40, stack: 16, food: Food(hunger: 2)),
  ItemType.rgb('cooked_mutton', 0.60, 0.35, 0.25, stack: 16, food: _wellFed5),
  ItemType.rgb('raw_chicken', 0.90, 0.75, 0.70, stack: 16, food: Food(hunger: 2)),
  ItemType.rgb('cooked_chicken', 0.75, 0.55, 0.35, stack: 16, food: _wellFed5),
  ItemType.rgb(
    'bread',
    0.80,
    0.60,
    0.30,
    stack: 16,
    food: Food(hunger: 5, heal: 4.0, effect: 'well_fed', seconds: 20.0),
  ),
  ItemType.rgb('rotten_flesh', 0.45, 0.35, 0.25, stack: 16, food: Food(hunger: 1, effect: 'poison', seconds: 4.0)),
  ItemType.rgb(
    'mushroom_stew',
    0.75,
    0.55,
    0.40,
    stack: 16,
    food: Food(hunger: 6, heal: 8.0, effect: 'well_fed', seconds: 20.0),
  ),
  ItemType.rgb('raw_fish', 0.60, 0.70, 0.75, stack: 16, food: Food(hunger: 2)),
  ItemType.rgb('cooked_fish', 0.80, 0.65, 0.45, stack: 16, food: _wellFed5),
  ItemType.rgb('raw_salmon', 0.90, 0.45, 0.40, stack: 16, food: Food(hunger: 3)),
  ItemType.rgb('cooked_salmon', 0.85, 0.50, 0.35, stack: 16, food: _wellFed6),
  ItemType.rgb('melon_slice', 0.90, 0.35, 0.40, stack: 16, food: Food(hunger: 2, heal: 1.0)),
  // A cow fills a bucket with milk (`mobTable`): it heals a little and cures every bad effect.
  ItemType.rgb('milk_bucket', 0.96, 0.96, 0.94, stack: 1, food: Food(heal: 2.0, cures: true, leaves: 'bucket')),
  // Potions, drunk as food is eaten.
  ItemType.rgb('health_potion', 0.95, 0.20, 0.35, stack: 16, food: Food(heal: 30.0)),
  ItemType.rgb(
    'speed_potion',
    0.45,
    0.85,
    0.95,
    name: 'Swiftness Potion',
    stack: 16,
    food: Food(effect: 'speed', seconds: 60.0),
  ),
  ItemType.rgb(
    'regen_potion',
    0.95,
    0.40,
    0.60,
    name: 'Regeneration Potion',
    stack: 16,
    food: Food(effect: 'regen', seconds: 30.0),
  ),
  ItemType.rgb('strength_potion', 0.90, 0.30, 0.25, stack: 16, food: Food(effect: 'strength', seconds: 60.0)),
  ItemType.rgb('resistance_potion', 0.70, 0.70, 0.75, stack: 16, food: Food(effect: 'resistance', seconds: 60.0)),
  ItemType.rgb('haste_potion', 0.95, 0.85, 0.35, stack: 16, food: Food(effect: 'haste', seconds: 60.0)),
  ItemType.rgb('antidote', 0.60, 0.90, 0.60, stack: 16, food: Food(cures: true)),
  // Tools by tier (wooden 1 to diamond 4): durability 60 × tier², damage by kind.
  ItemType.rgb('wooden_pickaxe', 0.70, 0.52, 0.30, stack: 1, tool: 'pickaxe', tier: 1, damage: 3, durability: 60),
  ItemType.rgb('wooden_axe', 0.70, 0.52, 0.30, stack: 1, tool: 'axe', tier: 1, damage: 4, durability: 60),
  ItemType.rgb('wooden_shovel', 0.70, 0.52, 0.30, stack: 1, tool: 'shovel', tier: 1, damage: 2, durability: 60),
  ItemType.rgb('wooden_hoe', 0.70, 0.52, 0.30, stack: 1, tool: 'hoe', tier: 1, damage: 1, durability: 60),
  ItemType.rgb('stone_pickaxe', 0.55, 0.55, 0.57, stack: 1, tool: 'pickaxe', tier: 2, damage: 4, durability: 240),
  ItemType.rgb('stone_axe', 0.55, 0.55, 0.57, stack: 1, tool: 'axe', tier: 2, damage: 5, durability: 240),
  ItemType.rgb('stone_shovel', 0.55, 0.55, 0.57, stack: 1, tool: 'shovel', tier: 2, damage: 3, durability: 240),
  ItemType.rgb('iron_pickaxe', 0.85, 0.85, 0.88, stack: 1, tool: 'pickaxe', tier: 3, damage: 5, durability: 540),
  ItemType.rgb('iron_axe', 0.85, 0.85, 0.88, stack: 1, tool: 'axe', tier: 3, damage: 6, durability: 540),
  ItemType.rgb('iron_shovel', 0.85, 0.85, 0.88, stack: 1, tool: 'shovel', tier: 3, damage: 4, durability: 540),
  ItemType.rgb('diamond_pickaxe', 0.45, 0.90, 0.88, stack: 1, tool: 'pickaxe', tier: 4, damage: 6, durability: 960),
  ItemType.rgb('diamond_axe', 0.45, 0.90, 0.88, stack: 1, tool: 'axe', tier: 4, damage: 7, durability: 960),
  ItemType.rgb('diamond_shovel', 0.45, 0.90, 0.88, stack: 1, tool: 'shovel', tier: 4, damage: 5, durability: 960),
  ItemType.rgb('shears', 0.78, 0.78, 0.82, stack: 1, tool: 'shears', tier: 3, damage: 1, durability: 540),
  // Weapons: durability 40 + 50 × tier. Swords and daggers swing; bows and staves shoot (`shots`).
  ItemType.rgb('wooden_sword', 0.70, 0.52, 0.30, stack: 1, tool: 'sword', tier: 1, damage: 6, durability: 90),
  ItemType.rgb('stone_sword', 0.55, 0.55, 0.57, stack: 1, tool: 'sword', tier: 2, damage: 8, durability: 140),
  ItemType.rgb('iron_sword', 0.85, 0.85, 0.88, stack: 1, tool: 'sword', tier: 3, damage: 10, durability: 190),
  ItemType.rgb('diamond_sword', 0.45, 0.90, 0.88, stack: 1, tool: 'sword', tier: 4, damage: 12, durability: 240),
  ItemType.rgb('ancient_blade', 0.80, 0.70, 0.35, stack: 1, tool: 'sword', tier: 4, damage: 14, durability: 240),
  ItemType.rgb(
    'dagger',
    0.80,
    0.80,
    0.85,
    stack: 1,
    tool: 'sword',
    tier: 2,
    damage: 4,
    durability: 140,
    shape: daggerShape,
  ),
  ItemType.rgb(
    'iron_dagger',
    0.85,
    0.85,
    0.90,
    name: 'Iron Daggers',
    stack: 1,
    tool: 'sword',
    tier: 3,
    damage: 6,
    durability: 190,
    shape: ironDaggerShape,
  ),
  ItemType.rgb(
    'bow',
    0.60,
    0.42,
    0.22,
    stack: 1,
    tier: 1,
    damage: 6,
    durability: 90,
    launcher: Launcher(shot: 'arrow', ammo: 'arrow'),
  ),
  ItemType.rgb(
    'longbow',
    0.50,
    0.32,
    0.15,
    stack: 1,
    tier: 3,
    damage: 10,
    durability: 190,
    launcher: Launcher(shot: 'long_arrow', ammo: 'arrow'),
  ),
  // A staff's bolt spends no item; what it costs (mana) is the classes' (VA-Zj).
  ItemType.rgb(
    'staff',
    0.55,
    0.35,
    0.75,
    name: 'Apprentice Staff',
    stack: 1,
    tier: 1,
    damage: 7,
    durability: 90,
    launcher: Launcher(shot: 'bolt'),
    shape: staffShape,
  ),
  ItemType.rgb(
    'crystal_staff',
    0.65,
    0.45,
    0.95,
    stack: 1,
    tier: 3,
    damage: 12,
    durability: 190,
    launcher: Launcher(shot: 'crystal_bolt'),
    shape: crystalStaffShape,
  ),
  // Armour: one piece, worn on the chest.
  ItemType.rgb('leather_armor', 0.65, 0.42, 0.25, stack: 1, armor: Armor('chest', 2)),
  ItemType.rgb('iron_armor', 0.85, 0.85, 0.88, stack: 1, armor: Armor('chest', 5)),
  ItemType.rgb('diamond_armor', 0.45, 0.90, 0.88, stack: 1, armor: Armor('chest', 8)),
];

const Food _wellFed5 = Food(hunger: 5, heal: 5.0, effect: 'well_fed', seconds: 20.0);
const Food _wellFed6 = Food(hunger: 6, heal: 6.0, effect: 'well_fed', seconds: 20.0);

/// What the bows and the staves shoot: an arrow falls, a bolt flies straight
/// and glows. A shot's damage is its weapon's (a staff's bolt six tenths of
/// it).
const Map<String, ProjectileSpec> shots = {
  'arrow': ProjectileSpec(speed: 36.0, gravity: 14.0, damage: 6.0, knockback: 5.0, radius: 0.05),
  'long_arrow': ProjectileSpec(speed: 36.0, gravity: 14.0, damage: 10.0, knockback: 5.0, radius: 0.05),
  'bolt': ProjectileSpec(
    kind: 'bolt',
    speed: 26.0,
    gravity: 0.0,
    damage: 4.2,
    knockback: 3.0,
    radius: 0.35,
    thickness: 0.3,
    length: 0.3,
    color: 0xFF7326,
    glow: true,
    light: 4.0,
    trail: 1.2,
  ),
  'crystal_bolt': ProjectileSpec(
    kind: 'bolt',
    speed: 26.0,
    gravity: 0.0,
    damage: 7.2,
    knockback: 3.0,
    radius: 0.35,
    thickness: 0.3,
    length: 0.3,
    color: 0xA673F2,
    glow: true,
    light: 4.0,
    trail: 1.2,
  ),
};

/// A staff: a shaft thirteen voxels tall and, on top, a three-voxel cube of
/// its colour, the gem.
const CustomItemShape staffShape = CustomItemShape([
  (IVec3(0, 0, 0), IVec3(0, 12, 0), _handle),
  (IVec3(-1, 12, -1), IVec3(1, 14, 1), 0x8C59BF),
], grip: ItemGrip.flat);

/// The crystal staff: the staff with a paler gem.
const CustomItemShape crystalStaffShape = CustomItemShape([
  (IVec3(0, 0, 0), IVec3(0, 12, 0), _handle),
  (IVec3(-1, 12, -1), IVec3(1, 14, 1), 0xA673F2),
], grip: ItemGrip.flat);

/// A dagger: a short grip, a crossguard and a blade six voxels long.
const CustomItemShape daggerShape = CustomItemShape([
  (IVec3(0, 0, 0), IVec3(0, 2, 0), _handle),
  (IVec3(-1, 3, 0), IVec3(1, 3, 0), _guard),
  (IVec3(0, 4, 0), IVec3(0, 9, 0), 0xCCCCD9),
], grip: ItemGrip.flat);

/// The iron daggers: the dagger with a brighter blade.
const CustomItemShape ironDaggerShape = CustomItemShape([
  (IVec3(0, 0, 0), IVec3(0, 2, 0), _handle),
  (IVec3(-1, 3, 0), IVec3(1, 3, 0), _guard),
  (IVec3(0, 4, 0), IVec3(0, 9, 0), 0xD9D9E6),
], grip: ItemGrip.flat);

const int _handle = 0x73522E, _guard = 0x808080;
