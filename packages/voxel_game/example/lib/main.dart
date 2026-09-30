// A small voxel sandbox in one declaration: `flutter run -d macos`.
import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

void main() => runVoxelGame(game, title: 'Voxel game', saveSlot: 'world1');

const game = VoxelGameSpec(
  seed: 2024,
  // 1. Blocks. Air is added for you; the order is the save format.
  blocks: [
    BlockType('stone', color: 0x7F7F84, hardness: 1.5, tool: 'pickaxe', tier: 1, drop: 'cobblestone'),
    BlockType('cobblestone', color: 0x6E6E70, hardness: 2.0, tool: 'pickaxe'),
    BlockType('dirt', color: 0x8A5E3B, hardness: 0.5, tool: 'shovel', turnsWith: {'hoe': 'farmland'}),
    BlockType('grass', color: 0x5C9E3A, hardness: 0.6, tool: 'shovel', drop: 'dirt', turnsWith: {'hoe': 'farmland'}),
    BlockType('sand', color: 0xDCCB8A, hardness: 0.5, tool: 'shovel', falls: true),
    BlockType('log', color: 0x6B4F2A, hardness: 2.0, tool: 'axe'),
    BlockType('leaves', color: 0x3F8A2E, hardness: 0.2, opaque: false),
    BlockType('planks', color: 0xB08850, hardness: 2.0, tool: 'axe'),
    BlockType('coal_ore', color: 0x3A3A3E, hardness: 3.0, tool: 'pickaxe', tier: 1, drop: 'coal'),
    // A torch stands on a floor; put against a wall it is a wall torch, which leans on it.
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
    BlockType('stairs_e', color: 0xB08850, shape: BlockShape.stairsE, hardness: 2.0, tool: 'axe', drop: 'stairs'),
    BlockType('stairs_s', color: 0xB08850, shape: BlockShape.stairsS, hardness: 2.0, tool: 'axe', drop: 'stairs'),
    BlockType('stairs_w', color: 0xB08850, shape: BlockShape.stairsW, hardness: 2.0, tool: 'axe', drop: 'stairs'),
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
    ),
    BlockType(
      'wheat_2',
      color: 0xD8BE50,
      shape: BlockShape.cross,
      solid: false,
      hardness: 0,
      support: Support.below(on: {'farmland'}),
      loot: LootTable([LootEntry('wheat', 1, 3, 1.0), LootEntry('seeds', 1, 2, 1.0)]),
    ),
    // A chest: use opens it beside the bag; what it holds is saved, and spills when it breaks.
    BlockType('chest', color: 0x8A5A2A, hardness: 2.0, tool: 'axe', storage: Storage()),
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
    ItemType('wool_cap', color: 0xE8E8E8, stack: 1, armor: Armor('head', 1)),
    ItemType('wool_tunic', color: 0xE8E8E8, stack: 1, armor: Armor('chest', 3)),
    ItemType('door', color: 0x9A7040, block: 'door_z', stack: 16),
    // A bucket scoops a water source with use, and pours it back.
    ItemType('bucket', color: 0x8A6A40, stack: 16, bucket: Bucket.empty({'water': 'water_bucket'})),
    ItemType('water_bucket', color: 0x3366CC, stack: 1, bucket: Bucket.full('water', empties: 'bucket')),
    ItemType('wooden_hoe', color: 0xB08850, tool: 'hoe', tier: 1, stack: 1, durability: 60),
    ItemType('seeds', color: 0x7FA040, block: 'wheat_0'),
    ItemType('wheat', color: 0xD8BE50),
    ItemType('bread', color: 0xB8864A, food: Food(hunger: 5)),
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
  ],
  // Status effects: what a food starts, what the player carries.
  effects: [EffectType('regeneration', 'Regeneration', 0.9, 0.35, 0.55, period: 2.0, heal: 1.0)],
  // 3. The world: biomes chosen by climate, trees, ores.
  world: WorldGenSpec(
    bedrock: 'stone',
    biomes: [
      Biome(
        'forest',
        top: 'grass',
        under: 'dirt',
        climate: Climate.wet,
        trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')],
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
    beach: Biome('beach', top: 'sand'),
    ores: [Ore('coal_ore', share: 0.11)],
  ),
  // 4. The player: what they start with, and hunger that food fills.
  player: PlayerSpec(
    startingItems: {'wooden_pickaxe': 1, 'planks': 16, 'torch': 8, 'apple': 4, 'wool_cap': 1},
    hunger: HungerSpec(),
  ),
  // 5. Creatures: a body, a brain (goals; the lower priority wins), drops and when they spawn.
  mobs: [
    MobSpec(
      'sheep',
      hp: 8,
      speed: 2.0,
      halfWidth: 0.45,
      height: 1.2,
      rig: Rig.quadruped(body: 0xEEEEEE, head: 0xD8C8B0),
      brain: [FleeWhenHurt(), LookAtPlayer(), Wander()],
      drops: [Drop('wool', 1, 2), Drop('mutton', 1, 2)],
      spawn: SpawnRule.daylight(),
    ),
    MobSpec(
      'zombie',
      hp: 20,
      speed: 2.6,
      rig: Rig.humanoid(skin: 0x5E9A5A, shirt: 0x3A6A9A, armsForward: true, redEyes: true),
      brain: [MeleeAttack(damage: 3), Hunt(range: 18), Wander()],
      spawn: SpawnRule.dark(),
    ),
  ],
  // 6. Screens of the game's own: this one is a button in the game menu (Esc, or ⏸ on a phone).
  screens: {'controls': ScreenSpec(_controls, menu: 'Controls')},
);

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
              'WASD walk · Space jump · Shift run · Ctrl sneak\n'
              'Left click mine and hit · Right click place, use, eat, wear\n'
              'E bag · Q drop · V view · Esc menu\n'
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
