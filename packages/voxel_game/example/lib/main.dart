// A small voxel sandbox in one declaration: `flutter run -d macos`.
import 'package:voxel_game/voxel_game.dart';

void main() => runVoxelGame(game, title: 'Voxel game', saveSlot: 'world1');

const game = VoxelGameSpec(
  seed: 2024,
  // 1. Blocks. Air is added for you; the order is the save format.
  blocks: [
    BlockType('stone', color: 0x7F7F84, hardness: 1.5, tool: 'pickaxe', tier: 1, drop: 'cobblestone'),
    BlockType('cobblestone', color: 0x6E6E70, hardness: 2.0, tool: 'pickaxe'),
    BlockType('dirt', color: 0x8A5E3B, hardness: 0.5, tool: 'shovel'),
    BlockType('grass', color: 0x5C9E3A, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType('sand', color: 0xDCCB8A, hardness: 0.5, tool: 'shovel'),
    BlockType('log', color: 0x6B4F2A, hardness: 2.0, tool: 'axe'),
    BlockType('leaves', color: 0x3F8A2E, hardness: 0.2, opaque: false),
    BlockType('planks', color: 0xB08850, hardness: 2.0, tool: 'axe'),
    BlockType('coal_ore', color: 0x3A3A3E, hardness: 3.0, tool: 'pickaxe', tier: 1, drop: 'coal'),
    BlockType('torch', color: 0xFFD070, shape: BlockShape.torch, solid: false, hardness: 0, light: 14),
    BlockType.liquid('water', color: 0x3366CC),
    BlockType.liquid('water_flow', color: 0x3366CC, kind: 'water', source: false),
  ],
  // 2. Items that are not blocks, and how to craft things.
  items: [
    ItemType('coal', color: 0x202020),
    ItemType('wooden_pickaxe', color: 0xB08850, tool: 'pickaxe', tier: 1, stack: 1, durability: 60, damage: 2),
    ItemType('wool', color: 0xEEEEEE),
  ],
  recipes: [
    Recipe('planks', 4, {'log': 1}),
    Recipe('torch', 4, {'coal': 1, 'planks': 1}),
    Recipe('wooden_pickaxe', 1, {'planks': 5}),
  ],
  // 3. The world: biomes chosen by climate, trees, ores.
  world: WorldGenSpec(
    bedrock: 'stone',
    biomes: [
      Biome('forest', top: 'grass', under: 'dirt', climate: Climate.wet, trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')], treeChance: 90),
      Biome('plains', top: 'grass', under: 'dirt', trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')], treeChance: 12),
    ],
    beach: Biome('beach', top: 'sand'),
    ores: [Ore('coal_ore', share: 0.11)],
  ),
  // 4. The player and what they start with.
  player: PlayerSpec(startingItems: {'wooden_pickaxe': 1, 'planks': 16, 'torch': 8}),
  // 5. Creatures: a body, a brain (goals; the lower priority wins), drops and when they spawn.
  mobs: [
    MobSpec('sheep', hp: 8, speed: 2.0, halfWidth: 0.45, height: 1.2, rig: Rig.quadruped(body: 0xEEEEEE, head: 0xD8C8B0),
        brain: [FleeWhenHurt(), LookAtPlayer(), Wander()], drops: [Drop('wool', 1, 2)], spawn: SpawnRule.daylight()),
    MobSpec('zombie', hp: 20, speed: 2.6, rig: Rig.humanoid(skin: 0x5E9A5A, shirt: 0x3A6A9A, armsForward: true, redEyes: true),
        brain: [MeleeAttack(damage: 3), Hunt(range: 18), Wander()], spawn: SpawnRule.dark()),
  ],
);
