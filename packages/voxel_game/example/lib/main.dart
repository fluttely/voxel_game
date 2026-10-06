// A small voxel sandbox in one declaration: `flutter run -d macos`.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

// The title lists the worlds; one made Creative flies (F, or the ✈ button on a phone). A new world also picks
// how its clock reads, a choice of the game's own that the clock system reads back. The kit's HUD carries a bar
// of the game's own: the stamina a run spends.
void main() => runVoxelGame(
  game,
  title: 'Voxel game',
  menu: const TitleSpec(
    name: 'Voxel game',
    worldOptions: [
      WorldOption('clock', label: 'Clock', choices: {'24h': '24-hour clock', '12h': '12-hour clock'}),
    ],
  ),
  hud: hud,
);

/// The kit's HUD with the stamina's bar under the hearts.
Widget hud(BuildContext context, VoxelGame game) => DefaultHud(
  game,
  bars: [HudBar('Stamina', color: Colors.lightBlueAccent, fill: (game) => game.system<_Stamina>().left)],
);

const game = VoxelGameSpec(
  seed: 2024,
  // 1. Blocks. Air is added for you; the order is the save format. A block only the world makes (a wall torch, a
  //    stair turned, an open door, a lit lamp, a rail's curve) is no item a bag shows: `holdable: false`, and it
  //    drops the item that makes it.
  blocks: [
    BlockType('stone', color: 0x7F7F84, hardness: 1.5, tool: 'pickaxe', tier: 1, drop: 'cobblestone'),
    BlockType('cobblestone', color: 0x6E6E70, hardness: 2.0, tool: 'pickaxe'),
    BlockType('dirt', color: 0x8A5E3B, hardness: 0.5, tool: 'shovel', turnsWith: {'hoe': 'farmland'}),
    BlockType('grass', color: 0x5C9E3A, hardness: 0.6, tool: 'shovel', drop: 'dirt', turnsWith: {'hoe': 'farmland'}),
    BlockType('sand', color: 0xDCCB8A, hardness: 0.5, tool: 'shovel', falls: true, tags: {'step:sand'}),
    BlockType('log', color: 0x6B4F2A, hardness: 2.0, tool: 'axe'),
    // Shears cut leaves at once and get the leaves (the `mining` below).
    BlockType('leaves', color: 0x3F8A2E, hardness: 0.2, opaque: false, tags: {'leaves'}),
    BlockType('planks', color: 0xB08850, hardness: 2.0, tool: 'axe'),
    BlockType('coal_ore', color: 0x3A3A3E, hardness: 3.0, tool: 'pickaxe', tier: 1, drop: 'coal'),
    // A torch stands on a floor; put against a wall it is a wall torch, which leans on it. In hand it lights the way.
    BlockType(
      'torch',
      color: 0xFFD070,
      shape: BlockShape.torch,
      solid: false,
      hardness: 0,
      light: 14,
      support: Support.below(),
      onWall: 'wall_torch',
    ),
    BlockType.liquid('water', color: 0x3366CC),
    BlockType.liquid('water_flow', color: 0x3366CC, kind: 'water', source: false),
    BlockType(
      'wall_torch',
      color: 0xFFD070,
      shape: BlockShape.wallTorch,
      solid: false,
      hardness: 0,
      light: 14,
      drop: 'torch',
      support: Support.side(),
      holdable: false,
    ),
    // A door: two high, across the way you look, opened and closed with use.
    BlockType(
      'door_z',
      color: 0x9A7040,
      shape: BlockShape.panelZ,
      opaque: false,
      hardness: 1.0,
      tool: 'axe',
      drop: 'door',
      tall: true,
      support: Support.below(),
      facing: Facing.axis(x: 'door_x', z: 'door_z'),
      usedInto: 'door_z_open',
      holdable: false,
    ),
    BlockType(
      'door_x',
      color: 0x9A7040,
      shape: BlockShape.panelX,
      opaque: false,
      hardness: 1.0,
      tool: 'axe',
      drop: 'door',
      tall: true,
      support: Support.below(),
      usedInto: 'door_x_open',
      holdable: false,
    ),
    BlockType(
      'door_z_open',
      color: 0x9A7040,
      shape: BlockShape.panelX,
      solid: false,
      hardness: 1.0,
      tool: 'axe',
      drop: 'door',
      tall: true,
      support: Support.below(),
      usedInto: 'door_z',
      holdable: false,
    ),
    BlockType(
      'door_x_open',
      color: 0x9A7040,
      shape: BlockShape.panelZ,
      solid: false,
      hardness: 1.0,
      tool: 'axe',
      drop: 'door',
      tall: true,
      support: Support.below(),
      usedInto: 'door_x',
      holdable: false,
    ),
    // Stairs climb away from whoever places them.
    BlockType(
      'stairs',
      color: 0xB08850,
      shape: BlockShape.stairsN,
      hardness: 2.0,
      tool: 'axe',
      facing: Facing.compass(north: 'stairs', east: 'stairs_e', south: 'stairs_s', west: 'stairs_w'),
    ),
    BlockType(
      'stairs_e',
      color: 0xB08850,
      shape: BlockShape.stairsE,
      hardness: 2.0,
      tool: 'axe',
      drop: 'stairs',
      holdable: false,
    ),
    BlockType(
      'stairs_s',
      color: 0xB08850,
      shape: BlockShape.stairsS,
      hardness: 2.0,
      tool: 'axe',
      drop: 'stairs',
      holdable: false,
    ),
    BlockType(
      'stairs_w',
      color: 0xB08850,
      shape: BlockShape.stairsW,
      hardness: 2.0,
      tool: 'axe',
      drop: 'stairs',
      holdable: false,
    ),
    // Farming: tall grass sometimes drops seeds, a hoe tills the ground, wheat grows on it in the light.
    BlockType(
      'tall_grass',
      color: 0x6AAE44,
      shape: BlockShape.cross,
      solid: false,
      hardness: 0,
      support: Support.below(),
      loot: LootTable([LootEntry('seeds', 1, 1, 0.4)]),
    ),
    BlockType('farmland', color: 0x5A3A20, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType(
      'wheat_0',
      color: 0x6FA83A,
      shape: BlockShape.cross,
      solid: false,
      hardness: 0,
      drop: 'seeds',
      support: Support.below(on: {'farmland'}),
      grows: Growth('wheat_1', seconds: 40),
      holdable: false,
    ),
    BlockType(
      'wheat_1',
      color: 0x9AAA38,
      shape: BlockShape.cross,
      solid: false,
      hardness: 0,
      drop: 'seeds',
      support: Support.below(on: {'farmland'}),
      grows: Growth('wheat_2', seconds: 40),
      holdable: false,
    ),
    BlockType(
      'wheat_2',
      color: 0xD8BE50,
      shape: BlockShape.cross,
      solid: false,
      hardness: 0,
      support: Support.below(on: {'farmland'}),
      loot: LootTable([LootEntry('wheat', 1, 3, 1.0), LootEntry('seeds', 1, 2, 1.0)]),
      holdable: false,
    ),
    // A chest: use opens it beside the bag; what it holds is saved, and spills when it breaks.
    BlockType('chest', color: 0x8A5A2A, hardness: 2.0, tool: 'axe', storage: Storage()),
    // A bed: use sets the spawn there and, at night, sleeps until morning once every player does.
    BlockType('bed', color: 0xB83A3A, shape: BlockShape.slab, opaque: false, hardness: 0.5, tool: 'axe', bed: true),
    // A portal: an obsidian frame, lit with flint and steel, fills with this; stand in it to cross.
    BlockType('obsidian', color: 0x1E1430, hardness: 10.0, tool: 'pickaxe', tier: 1),
    BlockType('portal', color: 0x8A3CF0, solid: false, alpha: 0.6, light: 11, hardness: -1, drop: '', holdable: false),
    // The underworld's own: rock, sand, light from the ceilings, a floor and roof nothing breaks, a lava sea.
    BlockType('hellstone', color: 0x6E2A2A, hardness: 0.4, tool: 'pickaxe'),
    BlockType('soul_sand', color: 0x54402F, hardness: 0.5, tool: 'shovel', speed: 0.6, tags: {'step:sand'}),
    BlockType('glowstone', color: 0xF0D27A, hardness: 0.3, light: 15),
    BlockType('bedrock', color: 0x2A2A2E, hardness: -1),
    BlockType.liquid('lava', color: 0xE0601A, alpha: 0.9, light: 15),
    // The ground's dress: dark stone in the deep, snow on the peaks and the tundra, gravel, swamp mud, ice.
    BlockType('dark_stone', color: 0x4A4A52, hardness: 2.0, tool: 'pickaxe', tier: 1, drop: 'cobblestone'),
    BlockType('snow', color: 0xF2F6FA, hardness: 0.3, tool: 'shovel', tags: {'step:snow'}),
    BlockType('gravel', color: 0x857F7A, hardness: 0.6, tool: 'shovel', falls: true, tags: {'step:sand'}),
    BlockType('mud', color: 0x4A3A2C, hardness: 0.5, tool: 'shovel', speed: 0.7),
    BlockType('ice', color: 0xA8CCF0, alpha: 0.8, hardness: 0.5, speed: 1.3),
    BlockType('spruce_log', color: 0x4A3420, hardness: 2.0, tool: 'axe', drop: 'log'),
    BlockType('spruce_leaves', color: 0x2E5A38, hardness: 0.2, opaque: false, tags: {'leaves'}),
    // What grows: cacti two or three tall, melons in patches, reeds beside water.
    BlockType('cactus', color: 0x4E8A32, hardness: 0.4, support: Support.below(on: {'sand', 'cactus'})),
    BlockType('melon', color: 0x6AA030, hardness: 1.0, tool: 'axe'),
    BlockType('reeds', color: 0x8AB860, shape: BlockShape.cross, solid: false, hardness: 0, support: Support.below()),
    // What structures are built of: bricks, ladders, fences, slabs, glass, a rail.
    BlockType('stone_bricks', color: 0x7A7A7E, hardness: 2.0, tool: 'pickaxe', tier: 1),
    BlockType('mossy_bricks', color: 0x5E7A5A, hardness: 2.0, tool: 'pickaxe', tier: 1),
    BlockType('ladder', color: 0x9A7040, shape: BlockShape.ladder, solid: false, opaque: false, hardness: 0.4),
    BlockType('fence', color: 0xB08850, shape: BlockShape.fence, opaque: false, hardness: 2.0, tool: 'axe'),
    BlockType('slab', color: 0xB08850, shape: BlockShape.slab, opaque: false, hardness: 2.0, tool: 'axe'),
    BlockType('glass', color: 0xCDE6F0, alpha: 0.35, hardness: 0.3, drop: ''),
    BlockType('rail', color: 0x8A8478, shape: BlockShape.railEw, solid: false, opaque: false, hardness: 0.7),
    // Circuits (the `signals` below): a wire, a lever, a lamp, pistons and powered rails, each state a block.
    BlockType('wire', color: 0x701010, shape: BlockShape.wire, solid: false, hardness: 0, support: Support.below()),
    BlockType(
      'wire_lit',
      color: 0xFF3020,
      shape: BlockShape.wire,
      solid: false,
      hardness: 0,
      light: 3,
      drop: 'wire',
      support: Support.below(),
      holdable: false,
    ),
    BlockType('lever', color: 0x806040, shape: BlockShape.torch, solid: false, hardness: 0, support: Support.below()),
    BlockType(
      'lever_on',
      color: 0xE04030,
      shape: BlockShape.torch,
      solid: false,
      hardness: 0,
      light: 4,
      drop: 'lever',
      support: Support.below(),
      holdable: false,
    ),
    BlockType('lamp', color: 0x6A4A2A, hardness: 0.3),
    BlockType('lamp_lit', color: 0xFFD080, hardness: 0.3, light: 15, drop: 'lamp', holdable: false),
    // A plate powers while a body stands on it; TNT powered is lit, and bursts three seconds on.
    BlockType('plate', color: 0x9A9A9A, shape: BlockShape.slab, opaque: false, hardness: 0.5, tool: 'pickaxe'),
    BlockType('tnt', color: 0xD03020, hardness: 0),
    // What a desert temple is built of.
    BlockType('sandstone', color: 0xD8C88A, hardness: 0.8, tool: 'pickaxe'),
    // A piston pushes away from whoever places it; out, it is the grey block.
    BlockType(
      'piston',
      color: 0x9E8056,
      hardness: 1.5,
      tool: 'pickaxe',
      facing: Facing.compass(north: 'piston', east: 'piston_e', south: 'piston_s', west: 'piston_w'),
    ),
    BlockType('piston_e', color: 0x9E8056, hardness: 1.5, tool: 'pickaxe', drop: 'piston', holdable: false),
    BlockType('piston_s', color: 0x9E8056, hardness: 1.5, tool: 'pickaxe', drop: 'piston', holdable: false),
    BlockType('piston_w', color: 0x9E8056, hardness: 1.5, tool: 'pickaxe', drop: 'piston', holdable: false),
    BlockType('piston_out', color: 0x808087, hardness: 1.5, tool: 'pickaxe', drop: 'piston', holdable: false),
    BlockType('piston_e_out', color: 0x808087, hardness: 1.5, tool: 'pickaxe', drop: 'piston', holdable: false),
    BlockType('piston_s_out', color: 0x808087, hardness: 1.5, tool: 'pickaxe', drop: 'piston', holdable: false),
    BlockType('piston_w_out', color: 0x808087, hardness: 1.5, tool: 'pickaxe', drop: 'piston', holdable: false),
    // A powered rail runs the way you look; a run of them lights eight rails on from the power.
    BlockType(
      'powered_rail',
      color: 0xB09048,
      shape: BlockShape.railEw,
      solid: false,
      opaque: false,
      hardness: 0.5,
      support: Support.below(),
      facing: Facing.axis(x: 'powered_rail', z: 'powered_rail_ns'),
    ),
    BlockType(
      'powered_rail_ns',
      color: 0xB09048,
      shape: BlockShape.railNs,
      solid: false,
      opaque: false,
      hardness: 0.5,
      drop: 'powered_rail',
      support: Support.below(),
      holdable: false,
    ),
    BlockType(
      'powered_rail_on',
      color: 0xFF8C40,
      shape: BlockShape.railEw,
      solid: false,
      opaque: false,
      hardness: 0.5,
      light: 4,
      drop: 'powered_rail',
      support: Support.below(),
      holdable: false,
    ),
    BlockType(
      'powered_rail_ns_on',
      color: 0xFF8C40,
      shape: BlockShape.railNs,
      solid: false,
      opaque: false,
      hardness: 0.5,
      light: 4,
      drop: 'powered_rail',
      support: Support.below(),
      holdable: false,
    ),
    // The rail's other shapes: a rail laid turns to meet the rails beside it — a straight, a curve, a slope up
    // onto a block — and each drops a rail.
    BlockType(
      'rail_ns',
      color: 0x8A8478,
      shape: BlockShape.railNs,
      solid: false,
      opaque: false,
      hardness: 0.7,
      drop: 'rail',
      holdable: false,
    ),
    BlockType(
      'rail_ne',
      color: 0x8A8478,
      shape: BlockShape.railNe,
      solid: false,
      opaque: false,
      hardness: 0.7,
      drop: 'rail',
      holdable: false,
    ),
    BlockType(
      'rail_nw',
      color: 0x8A8478,
      shape: BlockShape.railNw,
      solid: false,
      opaque: false,
      hardness: 0.7,
      drop: 'rail',
      holdable: false,
    ),
    BlockType(
      'rail_se',
      color: 0x8A8478,
      shape: BlockShape.railSe,
      solid: false,
      opaque: false,
      hardness: 0.7,
      drop: 'rail',
      holdable: false,
    ),
    BlockType(
      'rail_sw',
      color: 0x8A8478,
      shape: BlockShape.railSw,
      solid: false,
      opaque: false,
      hardness: 0.7,
      drop: 'rail',
      holdable: false,
    ),
    BlockType(
      'rail_slope_n',
      color: 0x8A8478,
      shape: BlockShape.railSlopeN,
      solid: false,
      opaque: false,
      hardness: 0.7,
      drop: 'rail',
      holdable: false,
    ),
    BlockType(
      'rail_slope_e',
      color: 0x8A8478,
      shape: BlockShape.railSlopeE,
      solid: false,
      opaque: false,
      hardness: 0.7,
      drop: 'rail',
      holdable: false,
    ),
    BlockType(
      'rail_slope_s',
      color: 0x8A8478,
      shape: BlockShape.railSlopeS,
      solid: false,
      opaque: false,
      hardness: 0.7,
      drop: 'rail',
      holdable: false,
    ),
    BlockType(
      'rail_slope_w',
      color: 0x8A8478,
      shape: BlockShape.railSlopeW,
      solid: false,
      opaque: false,
      hardness: 0.7,
      drop: 'rail',
      holdable: false,
    ),
  ],
  // 2. Items that are not blocks — tools, food (eaten with use), armour (worn with use), a door
  //    (placing its block), buckets, a hoe, seeds (placing wheat) — and how to craft things.
  items: [
    ItemType('coal', color: 0x202020),
    ItemType('wooden_pickaxe', color: 0xB08850, tool: 'pickaxe', tier: 1, stack: 1, durability: 60, damage: 2),
    ItemType('wool', color: 0xEEEEEE),
    ItemType('apple', color: 0xD03A2A, food: Food(hunger: 4)),
    ItemType('mutton', color: 0xC8705A, food: Food(hunger: 6)),
    ItemType('bowl', color: 0x9A7040),
    ItemType(
      'stew',
      color: 0xA0683A,
      stack: 1,
      food: Food(hunger: 6, heal: 4, effect: 'regeneration', seconds: 8, leaves: 'bowl'),
    ),
    ItemType('wool_cap', color: 0xE8E8E8, stack: 1, armor: Armor('head', 1), shape: ItemShape.cap),
    ItemType('wool_tunic', color: 0xE8E8E8, stack: 1, armor: Armor('chest', 3)),
    ItemType('door', color: 0x9A7040, block: 'door_z', stack: 16),
    // A bucket scoops a water source with use, and pours it back.
    ItemType('bucket', color: 0x8A6A40, stack: 16, bucket: Bucket.empty({'water': 'water_bucket'})),
    ItemType('water_bucket', color: 0x3366CC, stack: 1, bucket: Bucket.full('water', empties: 'bucket')),
    ItemType('wooden_hoe', color: 0xB08850, tool: 'hoe', tier: 1, stack: 1, durability: 60),
    ItemType('seeds', color: 0x7FA040, block: 'wheat_0'),
    ItemType('wheat', color: 0xD8BE50),
    ItemType('bread', color: 0xB8864A, food: Food(hunger: 5)),
    ItemType('flint_and_steel', color: 0x5A5A60, stack: 1, durability: 64),
    // A boat: put on water with use, ridden by a use on it, left with sneak, broken by a swing.
    ItemType('boat', color: 0x8C6133, stack: 1),
    // A minecart: put on a rail with use, ridden by a use on it and pushed with the move keys along its way.
    ItemType('minecart', color: 0x8C8C94, stack: 1),
    // A fishing rod: cast at water with use, and use again when something bites (the `fishing` below).
    ItemType('fishing_rod', color: 0x9E7340, stack: 1),
    ItemType('raw_fish', color: 0x99B3BF, food: Food(hunger: 2)),
    // Carried in the bag, it glides: hold G (or the button on a phone) in the air.
    ItemType('glider', color: 0xD04A30, stack: 1, glider: Glider()),
    // A bow shoots an arrow (the `shots` below) with attack, one of them spent from the bag.
    ItemType(
      'bow',
      color: 0x8A6034,
      stack: 1,
      durability: 200,
      launcher: Launcher(shot: 'arrow', ammo: 'arrow'),
    ),
    ItemType('arrow', color: 0xC8B090),
    // Shears: a use on a sheep shears it of its wool, which grows back; they cut leaves at once.
    ItemType('shears', color: 0xC8C8D0, tool: 'shears', stack: 1, durability: 120),
    // A bucket used on a cow is milk, which cures poison and burning and leaves the bucket.
    ItemType('milk_bucket', color: 0xF4F4F0, stack: 1, food: Food(heal: 2, cures: true, leaves: 'bucket')),
  ],
  recipes: [
    Recipe('planks', 4, {'log': 1}),
    Recipe('torch', 4, {'coal': 1, 'planks': 1}),
    Recipe('wooden_pickaxe', 1, {'planks': 5}),
    Recipe('bowl', 4, {'planks': 3}),
    Recipe('stew', 1, {'bowl': 1, 'apple': 1, 'mutton': 1}),
    Recipe('wool_cap', 1, {'wool': 3}),
    Recipe('wool_tunic', 1, {'wool': 5}),
    Recipe('door', 1, {'planks': 6}),
    Recipe('stairs', 4, {'planks': 6}),
    Recipe('bucket', 1, {'planks': 3}),
    Recipe('wooden_hoe', 1, {'planks': 3}),
    Recipe('bread', 1, {'wheat': 3}),
    Recipe('chest', 1, {'planks': 8}),
    Recipe('obsidian', 1, {'cobblestone': 4}),
    Recipe('flint_and_steel', 1, {'coal': 1, 'cobblestone': 1}),
    Recipe('wire', 8, {'coal': 2}),
    Recipe('lever', 1, {'cobblestone': 1, 'planks': 1}),
    Recipe('lamp', 1, {'torch': 1, 'planks': 4}),
    Recipe('tnt', 1, {'sand': 4, 'coal': 1}),
    Recipe('plate', 1, {'cobblestone': 2}),
    Recipe('piston', 1, {'planks': 3, 'cobblestone': 4, 'wire': 1}),
    Recipe('powered_rail', 6, {'planks': 2, 'cobblestone': 4, 'wire': 1}),
    Recipe('boat', 1, {'planks': 5}),
    Recipe('rail', 16, {'cobblestone': 6, 'planks': 1}),
    Recipe('minecart', 1, {'cobblestone': 5}),
    Recipe('fishing_rod', 1, {'planks': 3, 'wool': 2}),
    Recipe('glider', 1, {'wool': 6, 'planks': 2}),
    Recipe('bow', 1, {'planks': 3, 'wool': 3}),
    Recipe('arrow', 4, {'planks': 1, 'cobblestone': 1}),
    Recipe('shears', 1, {'cobblestone': 2}),
    Recipe('bed', 1, {'wool': 3, 'planks': 3}),
  ],
  // What the bow looses: fast, falling, six points of damage.
  shots: {'arrow': ProjectileSpec(speed: 36, gravity: 14, damage: 6, life: 5)},
  mining: MiningRules(
    cuts: {
      'shears': {'leaves'},
    },
  ),
  // Status effects: what a food starts, what the player carries.
  effects: [
    EffectType('regeneration', 'Regeneration', 0.9, 0.35, 0.55, period: 2.0, heal: 1.0),
    EffectType('poison', 'Poison', 0.3, 0.6, 0.2, period: 1.5, damage: 1.0, bad: true),
    // What the wisp's fire does to the player (a creature it hits burns by the kit's own rule).
    EffectType('burning', 'Burning', 1.0, 0.45, 0.1, period: 1.0, damage: 1.0, bad: true),
  ],
  // 3. The world: biomes chosen by climate (the first that holds), what covers their ground, the trees they
  //    grow by weight and the plants, dark stone in the deep, ores, and structures built of the game's blocks.
  world: WorldGenSpec(
    bedrock: 'stone',
    biomes: [
      Biome(
        'peaks',
        top: 'stone',
        climate: Climate.highlands,
        covers: [Cover('snow', minHeight: 101), Cover('gravel', perMille: 250)],
        trees: [TreeSpec.spruce(log: 'spruce_log', leaves: 'spruce_leaves', belowY: 96)],
        treeChance: 20,
        precipitation: Precipitation.snow,
      ),
      Biome(
        'tundra',
        top: 'snow',
        under: 'dirt',
        climate: Climate.cold,
        trees: [TreeSpec.spruce(log: 'spruce_log', leaves: 'spruce_leaves')],
        treeChance: 37,
        ice: 'ice',
        precipitation: Precipitation.snow,
      ),
      Biome(
        'desert',
        top: 'sand',
        climate: Climate.hotDry,
        plants: [Plant('cactus', perMille: 12, height: 2, maxHeight: 3)],
        precipitation: Precipitation.none,
      ),
      Biome(
        'swamp',
        top: 'grass',
        under: 'dirt',
        climate: Climate(minTemperature: 0.1, minHumidity: 0.42, maxHeight: 52),
        covers: [Cover('mud', perMille: 400, patch: 2)],
        pools: Pools(bed: 'mud'),
        trees: [TreeSpec(TreeShape.willow, log: 'log', leaves: 'leaves', minHeight: 9, maxHeight: 11)],
        treeChance: 27,
        // The low ground a swamp grows on is pressed flat, two blocks over the sea.
        flats: Flats(),
        plants: [Plant('reeds', perMille: 550, byWater: true), Plant('tall_grass', perMille: 280)],
      ),
      Biome(
        'jungle',
        top: 'grass',
        under: 'dirt',
        climate: Climate.hotWet,
        trees: [
          TreeSpec(TreeShape.jungle, log: 'log', leaves: 'leaves', minHeight: 16, maxHeight: 22, weight: 3),
          TreeSpec.oak(log: 'log', leaves: 'leaves'),
        ],
        treeChance: 47,
        plants: [Plant('melon', perMille: 12, spread: 2), Plant('tall_grass', perMille: 300)],
      ),
      Biome(
        'forest',
        top: 'grass',
        under: 'dirt',
        climate: Climate.wet,
        trees: [
          TreeSpec.oak(log: 'log', leaves: 'leaves', weight: 7),
          TreeSpec(TreeShape.bigOak, log: 'log', leaves: 'leaves', minHeight: 14, maxHeight: 18, weight: 3),
        ],
        treeChance: 90,
      ),
      Biome(
        'plains',
        top: 'grass',
        under: 'dirt',
        trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')],
        treeChance: 12,
        plants: [Plant('tall_grass', perMille: 60)],
      ),
    ],
    ocean: Biome('ocean', top: 'sand', covers: [Cover('gravel', perMille: 200)]),
    beach: Biome('beach', top: 'sand'),
    // Where it is colder still, the shore is snow and the shallows freeze.
    shores: [
      Biome(
        'frozen_shore',
        top: 'snow',
        under: 'sand',
        climate: Climate(maxTemperature: -0.4),
        ice: 'ice',
        precipitation: Precipitation.snow,
      ),
    ],
    strata: [Stratum('dark_stone', belowY: 22)],
    ores: [Ore('coal_ore', share: 0.11)],
    structures: [
      StructureSpec('village', _village, chance: 0.4, biomes: ['plains', 'forest']),
      StructureSpec('mine', _mine, chance: 0.3, regionChunks: 5, biomes: ['plains', 'forest', 'peaks', 'tundra']),
      StructureSpec('dungeon', _dungeon, chance: 0.4),
      StructureSpec('tower', _tower, chance: 0.25, regionChunks: 4),
      StructureSpec('camp', _camp, chance: 0.2, regionChunks: 4),
      StructureSpec('ruins', _ruins, chance: 0.3, regionChunks: 3, biomes: ['plains', 'forest', 'jungle']),
      StructureSpec('well', _well, chance: 0.2, regionChunks: 3, biomes: ['plains', 'desert']),
      StructureSpec('temple', _temple, chance: 0.5, regionChunks: 4, biomes: ['desert']),
    ],
  ),
  // Another dimension, a world of its own from the same seed: one great cave between a bedrock floor and roof,
  // a lava sea, soul sand where it is wet, glowstone hanging from the ceilings. No sky falls in it.
  dimensions: {
    'underworld': WorldGenSpec(
      cavern: CavernSpec(hangs: [Plant('glowstone', perMille: 40, height: 2)]),
      stone: 'hellstone',
      water: 'lava',
      seaLevel: 28,
      bedrock: 'bedrock',
      caves: CaveSpec.none,
      biomes: [
        Biome('soul_valley', top: 'soul_sand', climate: Climate.wet, precipitation: Precipitation.none),
        Biome('wastes', top: 'hellstone', precipitation: Precipitation.none),
      ],
      ores: [Ore('coal_ore', share: 0.05)],
    ),
  },
  // The way there: an obsidian frame around a hollow 2 wide and 3 tall, lit with flint and steel; two seconds
  // in it and the player crosses, a frame built on the far side for the way back.
  portals: [PortalSpec(frame: 'obsidian', portal: 'portal', lighter: 'flint_and_steel', to: 'underworld')],
  // Circuits: a lever powers a wire, and what the wire touches answers — a lamp lights, a piston pushes the block
  // in front of it, a run of powered rails lights up, TNT is lit (and lights the TNT its blast reaches).
  signals: SignalSpec(
    wire: ('wire', 'wire_lit'),
    levers: {'lever': 'lever_on'},
    plates: {'plate'},
    lamps: {'lamp': 'lamp_lit'},
    explosives: {'tnt': Explosive()},
    pistons: {
      'piston': 'piston_out',
      'piston_e': 'piston_e_out',
      'piston_s': 'piston_s_out',
      'piston_w': 'piston_w_out',
    },
    poweredRails: {'powered_rail': 'powered_rail_on', 'powered_rail_ns': 'powered_rail_ns_on'},
  ),
  // The weather: rain and storms rolled every few minutes (snow where a biome's precipitation is snow). The
  // underworld has a sky of its own: no sun, a dark red, and a haze closing in.
  sky: SkySpec(
    weather: WeatherSpec(),
    dimensions: {
      'underworld': DimensionSky(
        StillSky(zenith: 0x0F0303, horizon: 0x470D08, ground: 0x1F0505, ambient: 0xFF8C6B),
        haze: Haze(0x4C0F0A, 0.014),
      ),
    },
  ),
  // What a structure's chests hold, in place of an empty chest's nothing; a dungeon's may hold a weapon with a
  // bonus to its damage.
  structureLoot: {
    'temple': StructureLoot(
      LootTable([
        LootEntry('bread', 1, 3, 0.8),
        LootEntry('arrow', 4, 12, 0.7),
        LootEntry('tnt', 1, 2, 0.5),
        LootEntry('coal', 2, 6, 0.6),
      ]),
      bonus: LootBonus(['bow', 'wooden_pickaxe']),
    ),
    'dungeon': StructureLoot(
      LootTable([LootEntry('arrow', 6, 14, 0.8), LootEntry('bread', 1, 2, 0.6), LootEntry('glider', 1, 1, 0.15)]),
      bonus: LootBonus(['bow']),
    ),
  },
  // Music written as notes, synthesised at first play (no files): the meadow's by day and by night, wherever no
  // other plays (the jungle and the plains share it); its own in the desert, the snow and the swamp; the deep's
  // underground and the underworld's all through it. A recording put in the assets as `asset:` plays instead.
  sounds: SoundSpec(
    music: MusicSpec(
      tracks: {
        'meadow': MusicTrack(score: StockMusic.pastoral, title: 'Meadow'),
        'dunes': MusicTrack(score: StockMusic.arid, title: 'Dunes'),
        'frost': MusicTrack(score: StockMusic.frozen, title: 'Frost'),
        'marsh': MusicTrack(score: StockMusic.murky, title: 'Marsh'),
        'deep': MusicTrack(score: StockMusic.cavern, title: 'Deep'),
        'underworld': MusicTrack(score: StockMusic.infernal, title: 'Underworld'),
      },
      day: 'meadow',
      cave: 'deep',
      biomes: {'desert': 'dunes', 'tundra': 'frost', 'peaks': 'frost', 'swamp': 'marsh'},
      dimensions: {'underworld': 'underworld'},
    ),
  ),
  // 4. The player: what they start with, hunger that food fills, experience (a kill's, below), and one blow in
  //    ten a critical one.
  player: PlayerSpec(
    startingItems: {
      'wooden_pickaxe': 1,
      'planks': 16,
      'torch': 8,
      'bow': 1,
      'arrow': 32,
      'shears': 1,
      'bed': 1,
      'apple': 4,
      'wool_cap': 1,
      'glider': 1,
    },
    hunger: HungerSpec(),
    xp: XpSpec(),
    critChance: 0.1,
  ),
  // 5. Creatures: a body, a brain (goals; the lower priority wins), loot, experience and when they spawn.
  mobs: [
    MobSpec(
      'sheep',
      hp: 8,
      speed: 2.0,
      halfWidth: 0.45,
      height: 1.2,
      rig: Rig.quadruped(body: 0xEEEEEE, head: 0xD8C8B0),
      brain: [FleeWhenHurt(), LookAtPlayer(), Wander()],
      loot: LootTable([LootEntry('wool', 1, 2, 1.0), LootEntry('mutton', 1, 2, 1.0)]),
      xp: 5,
      // Shears take one to three wool off it; it grows back in two minutes.
      fleece: Fleece('wool'),
      spawn: SpawnRule.daylight(),
    ),
    // A cow fills a bucket with milk.
    MobSpec(
      'cow',
      hp: 10,
      speed: 2.0,
      halfWidth: 0.45,
      height: 1.4,
      rig: Rig.quadruped(body: 0x5A3A26, head: 0xE8E0D8),
      brain: [FleeWhenHurt(), LookAtPlayer(), Wander()],
      xp: 5,
      yields: {'bucket': 'milk_bucket'},
      spawn: SpawnRule.daylight(weight: 6, biomes: ['plains', 'forest']),
    ),
    // A wolf keeps to itself until hurt; mutton tames it (half the time) into a companion that heels and fights.
    MobSpec(
      'wolf',
      hp: 14,
      speed: 4.2,
      halfWidth: 0.4,
      height: 0.95,
      rig: Rig.quadruped(body: 0x8C8C94, head: 0x5A5A60),
      brain: [MeleeAttack(damage: 3), Hunt(whenProvoked: true), Wander()],
      loot: LootTable([LootEntry('mutton', 0, 1, 0.5)]),
      xp: 6,
      tameWith: ['mutton'],
      tameChance: 0.5,
      tamedBrain: [MeleeAttack(damage: 4), PetFight(), Heel()],
      spawn: SpawnRule.daylight(weight: 4, biomes: ['forest', 'tundra'], group: (1, 3), maxAlive: 4),
    ),
    // A horse: an apple tames it, and then a use rides it (sneak gets off).
    MobSpec(
      'horse',
      hp: 20,
      speed: 6.5,
      halfWidth: 0.5,
      height: 1.6,
      rig: Rig.quadruped(body: 0x7A4A26, head: 0x26180E),
      brain: [FleeWhenHurt(), Wander()],
      xp: 5,
      tameWith: ['apple'],
      tameChance: 0.6,
      tamedBrain: [MountWait()],
      mount: MountSpec(seat: 1.0),
      spawn: SpawnRule.daylight(weight: 5, biomes: ['plains'], group: (1, 2), maxAlive: 4),
    ),
    MobSpec(
      'zombie',
      hp: 20,
      speed: 2.6,
      rig: Rig.humanoid(skin: 0x5E9A5A, shirt: 0x3A6A9A, armsForward: true, redEyes: true),
      brain: [MeleeAttack(damage: 3), Hunt(range: 18), Wander()],
      xp: 15,
      // Grows with the player (tougher in caves), and burns under the noon sky.
      levels: MobLevels(),
      burnsInDaylight: true,
      spawn: SpawnRule.dark(),
    ),
    // A spider of the caves: its bite poisons.
    MobSpec(
      'cave_spider',
      hp: 10,
      speed: 4.0,
      halfWidth: 0.55,
      height: 0.7,
      rig: Rig.spider(),
      brain: [MeleeAttack(damage: 2), Hunt(range: 14), Wander()],
      loot: LootTable([LootEntry('wire', 0, 1, 0.5)]),
      xp: 10,
      levels: MobLevels(),
      onHit: HitEffect('poison', seconds: 6.0),
      spawn: SpawnRule.cave(),
    ),
    // A slime of the night, thickest in the swamp: it dies into two small ones.
    MobSpec(
      'slime',
      hp: 12,
      speed: 2.4,
      halfWidth: 0.5,
      height: 1.0,
      rig: Rig.blob(),
      gait: Gait.hop,
      brain: [MeleeAttack(damage: 2), Hunt(range: 14), Wander()],
      xp: 8,
      splitsInto: MobSplit('small_slime'),
      spawn: SpawnRule.dark(weight: 4, biomeWeights: {'swamp': 4.0}),
    ),
    MobSpec(
      'small_slime',
      hp: 4,
      speed: 2.8,
      halfWidth: 0.25,
      height: 0.5,
      rig: Rig.blob(),
      gait: Gait.hop,
      brain: [MeleeAttack(damage: 1), Hunt(range: 10), Wander()],
      xp: 2,
    ),
    // A wisp of the night: a ghost, drawn see-through, that drifts through walls and keeps its distance to throw
    // fire, which lights its way and sets the player burning.
    MobSpec(
      'wisp',
      hp: 10,
      speed: 3.0,
      height: 1.5,
      rig: Rig.humanoid(skin: 0xDCEAF4, shirt: 0xB4CCE4, pants: 0x94ACCC, redEyes: true),
      gait: Gait.fly,
      ghost: true,
      brain: [
        RangedAttack(projectile: _wispFire, range: 14),
        Hunt(range: 18),
        Wander(),
      ],
      xp: 12,
      spawn: SpawnRule.dark(weight: 2, maxAlive: 2),
    ),
    // A boss: rare, at night, one at a time; while it is about, its health is a bar at the top.
    MobSpec(
      'brute',
      hp: 80,
      speed: 2.2,
      halfWidth: 0.5,
      height: 2.4,
      rig: Rig.humanoid(skin: 0x4A6A3A, shirt: 0x5A2A2A, armsForward: true, redEyes: true),
      brain: [MeleeAttack(damage: 6), Hunt(range: 24), Wander()],
      loot: LootTable([LootEntry('coal', 2, 5, 1.0)]),
      xp: 60,
      spawn: SpawnRule.dark(weight: 1, maxAlive: 1),
      knockbackResistance: 0.6,
      boss: true,
    ),
  ],
  // Vehicles, one an item: the boat floats, rows forward and steers with the move keys; the minecart rides the
  // rails, rolls down slopes and is sped on by a powered rail.
  vehicles: [
    BoatSpec(item: 'boat'),
    CartSpec(item: 'minecart'),
  ],
  // Fishing: the rod casts at water; three to eight seconds later something bites, and a use within a second and a
  // half lands one catch — mostly a fish, now and then two, some junk, and once in twenty a lighter.
  fishing: FishingSpec(
    rod: 'fishing_rod',
    catches: LootTable.oneOf([
      LootEntry('raw_fish', 1, 1, 0.70),
      LootEntry('raw_fish', 2, 2, 0.10),
      LootEntry('bowl', 1, 1, 0.15),
      LootEntry('flint_and_steel', 1, 1, 0.05),
    ]),
  ),
  // 6. Actions of the game's own: keys, pad buttons and a button on a phone. A screen opens on one; a system
  // reads another in the step. Systems, made afresh for every world, hear what the player does; one saves.
  actions: [
    ActionSpec('controls', keys: [PhysicalKeyboardKey.f1], gamepad: [GamepadButton.back], touch: Icons.help_outline),
    ActionSpec('clock', keys: [PhysicalKeyboardKey.keyT], gamepad: [GamepadButton.x], touch: Icons.schedule),
    ActionSpec('wave', keys: [PhysicalKeyboardKey.keyH], gamepad: [GamepadButton.dpadLeft], touch: Icons.waving_hand),
  ],
  systems: _systems,
  // A use on a glowstone is the game's own: a prayer at a shrine (the `_Blessing` below), not a block built against.
  blockUses: {'glowstone': _pray},
  // 7. Screens of the game's own: this one is a button in the game menu (Esc, or ⏸ on a phone), and F1.
  screens: {'controls': ScreenSpec(_controls, menu: 'Controls', action: 'controls')},
  // 8. Messages of the game's own, in a hosted world: a wave goes to the host, which passes it on.
  messages: {'wave': _waved},
);

List<GameSystem> _systems() => [_Clock(), _Tally(), _Stamina(), _Blessing(), _Wave()];

// Stamina: a run spends it in six seconds and rest fills it in four. Spent, the player cannot run (a sprint veto)
// until it is back to a fifth. Its bar is in the HUD (`main` above).
class _Stamina extends GameSystem {
  double left = 1.0;
  bool _spent = false;

  @override
  void tick(VoxelGame game, double dt) {
    final p = game.player;
    p.sprintVetoes.putIfAbsent(
      'stamina',
      () =>
          () => _spent,
    );
    left = p.sprinting ? math.max(left - dt / 6.0, 0.0) : math.min(left + dt / 4.0, 1.0);
    if (left <= 0.0) _spent = true;
    if (left >= 0.2) _spent = false;
  }
}

// A glowstone is a shrine: the first use on one blesses the player with two more hearts for good, a boost a
// death does not take away, given again when the world loads.
class _Blessing extends SavedSystem {
  bool blessed = false;

  void bless(VoxelGame game) {
    if (blessed) {
      game.notify('The glow has blessed you already');
      return;
    }
    blessed = true;
    _give(game);
    game.player.hp = game.player.maxHp;
    game.notify('Blessed by the glow: two more hearts');
  }

  // The other players of a hosted world see it too: it rides the player's pose.
  void _give(VoxelGame game) {
    game.player.boosts['blessing'] = const Boost(maxHp: 4.0);
    game.player.poseExtras['blessed'] = true;
  }

  @override
  String get saveKey => 'blessing';

  @override
  Object? save(VoxelGame game) => blessed;

  @override
  void restore(VoxelGame game, Object? saved) {
    blessed = saved! as bool;
    if (blessed) _give(game);
  }
}

void _pray(VoxelGame game, IVec3 cell) => game.system<_Blessing>().bless(game);

// Tells the time of day when the clock action is pressed, as the world's clock option reads it, and the tally.
class _Clock extends GameSystem {
  @override
  void tick(VoxelGame game, double dt) {
    if (!game.gameplay || !game.actions.justPressed('clock')) return;
    final minutes = (game.timeOfDay * 24 * 60).floor();
    final h = minutes ~/ 60, m = (minutes % 60).toString().padLeft(2, '0');
    final time = game.worldInfo?.options['clock'] == '12h'
        ? '${(h + 11) % 12 + 1}:$m ${h < 12 ? 'am' : 'pm'}'
        : '$h:$m';
    final t = game.system<_Tally>();
    game.notify('It is $time · ${t.broken} broken, ${t.placed} placed, ${t.felled} felled in this world');
  }
}

// Counts the blocks the player breaks and places and the creatures they fell, kept in the world's save.
class _Tally extends SavedSystem {
  int broken = 0, placed = 0, felled = 0;

  @override
  String get saveKey => 'tally';

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    switch (event) {
      case BlockBroken():
        broken++;
      case BlockPlaced():
        placed++;
      case MobKilled(byPlayer: true):
        felled++;
      default:
    }
  }

  @override
  Object? save(VoxelGame game) => {'broken': broken, 'placed': placed, 'felled': felled};

  @override
  void restore(VoxelGame game, Object? saved) {
    final s = saved! as Map<String, Object?>;
    broken = s['broken']! as int;
    placed = s['placed']! as int;
    felled = s['felled']! as int;
  }
}

// A wave (H) to the other players of a hosted world: the host's goes to every client, a client's to the host.
class _Wave extends GameSystem {
  @override
  void tick(VoxelGame game, double dt) {
    if (!game.gameplay || !game.actions.justPressed('wave')) return;
    switch (game.session) {
      case null:
        game.notify('Nobody here to wave to: host the world, or join one');
        return;
      case final HostSession host:
        host.broadcast('wave', {'by': GameSession.hostPeer});
      case final client:
        client.sendToHost('wave', const {});
    }
    game.notify('You wave');
  }
}

// A wave heard. On the host it is a client's, passed on to the other clients; on a client, the host says who
// waved. Their name is over their head already; a blessing rides their pose.
void _waved(VoxelGame game, int from, NetMessage message) {
  final session = game.session!;
  final int by;
  if (session is HostSession) {
    by = from;
    session.broadcast('wave', {'by': from}, except: from);
  } else {
    by = message['by']! as int;
  }
  final who = session.players[by]!;
  game.notify('${who.name}${who.extras['blessed'] == true ? ', blessed by the glow,' : ''} waves');
}

// The kit's fireball, burning the player through the game's own effect as well as any creature it hits.
const _wispFire = ProjectileSpec(
  kind: 'fire',
  speed: 16.0,
  gravity: 0.0,
  damage: 3.0,
  radius: 0.25,
  thickness: 0.4,
  length: 0.4,
  color: 0xFF5A0D,
  glow: true,
  light: 4.0,
  trail: 1.6,
  burns: 4.0,
  onHit: HitEffect('burning', seconds: 4.0),
);

// The stock structures, each built of the game's blocks by name; a block left out is left out of the structure.
const _village = Village(
  floor: 'cobblestone',
  walls: 'planks',
  corners: 'log',
  roof: 'planks',
  path: 'gravel',
  wellRim: 'stone_bricks',
  water: 'water',
  roofRim: 'slab',
  window: 'glass',
  chest: 'chest',
  torch: 'torch',
  light: 'glowstone',
  farm: VillageFarm(soil: 'dirt', tilled: 'farmland', crop: 'wheat_2', fence: 'fence', torch: 'torch'),
);
const _mine = Mine(
  frame: 'cobblestone',
  posts: 'fence',
  roof: 'planks',
  ladder: 'ladder',
  beams: 'log',
  walls: 'cobblestone',
  rail: 'rail',
  light: 'torch',
  chest: 'chest',
  veins: {'coal_ore': 15},
);
const _dungeon = Dungeon(
  walls: 'stone_bricks',
  mossy: 'mossy_bricks',
  ladder: 'ladder',
  light: 'glowstone',
  chest: 'chest',
);
const _tower = Tower(walls: 'stone_bricks', mossy: 'mossy_bricks', floor: 'planks', ladder: 'ladder', chest: 'chest');
const _camp = Camp(cloth: 'planks', poles: 'log', chest: 'chest', light: 'torch');
const _ruins = Ruins(
  floor: 'cobblestone',
  ground: 'grass',
  walls: 'stone_bricks',
  mossy: 'mossy_bricks',
  plants: ['tall_grass'],
  chest: 'chest',
);
const _well = Well(rim: 'cobblestone', water: 'water', posts: 'fence', roof: 'planks');
// A desert temple: two chests in a chamber under a step pyramid, and a plate in its floor over TNT.
const _temple = Temple(stone: 'sandstone', chest: 'chest', light: 'glowstone', plate: 'plate', trap: 'tnt');

Widget _controls(BuildContext context, VoxelGame game) => ColoredBox(
  color: Colors.black54,
  child: Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Controls', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            const Text(
              'WASD walk · Space jump · Shift run, while the stamina lasts · Ctrl sneak\n'
              'Left click mine and hit · Right click place, use, eat, wear\n'
              'E bag · Q drop · V view · Esc menu\n'
              'G glide, with a glider in the bag · F fly, in a Creative world\n'
              'T the time · F1 these controls · Right click a glowstone to pray\n'
              'H wave to the other players, in a hosted world\n'
              'A phone: a stick at the left, the world is the button',
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: game.closeScreen, child: const Text('Back to the game')),
          ],
        ),
      ),
    ),
  ),
);
