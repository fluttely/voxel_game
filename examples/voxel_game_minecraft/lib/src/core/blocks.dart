import 'dart:typed_data';

import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';

/// The block table. INDEX IS THE SAVE CONTRACT: a chunk stores bytes and a save
/// file stores those bytes, so entries are appended, never reordered or removed.
/// Byte-for-byte the same order as the Godot POC (`src/core/blocks.gd`).
/// `BlockShape` and `CollisionBox` live in voxel_core (VP1.2).
enum ToolType { none, pickaxe, axe, shovel, sword, hoe, shears }

class BlockDef {
  const BlockDef(
    this.id,
    this.name,
    this.r,
    this.g,
    this.b, {
    this.a = 1.0,
    this.shape = BlockShape.cube,
    this.solid = true,
    this.opaque = true,
    this.hardness = 1.0,
    this.tool = ToolType.none,
    this.tier = 0,
    this.drop = '',
    this.light = 0,
    this.speedMult = 1.0,
  });

  final String id;
  final String name;
  final double r, g, b, a;
  final BlockShape shape;

  /// Stops a body.
  final bool solid;

  /// Occludes faces and stops light.
  final bool opaque;

  /// Seconds by hand; -1 unbreakable.
  final double hardness;
  final ToolType tool;

  /// 0 hand, 1 wood, 2 stone, 3 iron, 4 diamond.
  final int tier;

  /// Item id, "" for itself, "-" for nothing.
  final String drop;

  /// 0..15 emitted light.
  final int light;

  /// Stage 29: how the block under a walker's feet scales its speed (soul sand 0.5).
  final double speedMult;
}

class Blocks {
  Blocks._();

  static const int air = 0;

  static const List<BlockDef> defs = [
    BlockDef('air', 'Air', 0, 0, 0, solid: false, opaque: false, hardness: -1, drop: '-'),
    BlockDef('stone', 'Stone', 0.50, 0.50, 0.52, hardness: 3.0, tool: ToolType.pickaxe, tier: 1, drop: 'cobblestone'),
    BlockDef('dirt', 'Dirt', 0.55, 0.38, 0.24, hardness: 0.8, tool: ToolType.shovel),
    BlockDef('grass', 'Grass Block', 0.36, 0.64, 0.27, hardness: 0.9, tool: ToolType.shovel, drop: 'dirt'),
    BlockDef('sand', 'Sand', 0.87, 0.81, 0.60, hardness: 0.7, tool: ToolType.shovel),
    BlockDef('water', 'Water', 0.20, 0.42, 0.78, a: 0.62, shape: BlockShape.liquid, solid: false, opaque: false, hardness: -1, drop: '-'),
    BlockDef('oak_log', 'Oak Log', 0.43, 0.30, 0.17, hardness: 2.5, tool: ToolType.axe),
    BlockDef('oak_leaves', 'Oak Leaves', 0.25, 0.52, 0.19, hardness: 0.3, drop: '-'),
    BlockDef('gravel', 'Gravel', 0.56, 0.54, 0.51, hardness: 0.8, tool: ToolType.shovel),
    BlockDef('sandstone', 'Sandstone', 0.80, 0.74, 0.52, hardness: 1.5, tool: ToolType.pickaxe, tier: 1),
    BlockDef('snow', 'Snow', 0.94, 0.95, 0.98, hardness: 0.4, tool: ToolType.shovel),
    BlockDef('spruce_log', 'Spruce Log', 0.30, 0.20, 0.12, hardness: 2.5, tool: ToolType.axe),
    BlockDef('spruce_leaves', 'Spruce Leaves', 0.17, 0.37, 0.23, hardness: 0.3, drop: '-'),
    BlockDef('cactus', 'Cactus', 0.29, 0.56, 0.25, hardness: 0.5),
    BlockDef('coal_ore', 'Coal Ore', 0.30, 0.30, 0.31, hardness: 3.5, tool: ToolType.pickaxe, tier: 1, drop: 'coal'),
    BlockDef('iron_ore', 'Iron Ore', 0.66, 0.54, 0.46, hardness: 4.0, tool: ToolType.pickaxe, tier: 2, drop: 'raw_iron'),
    BlockDef('gold_ore', 'Gold Ore', 0.78, 0.66, 0.30, hardness: 4.0, tool: ToolType.pickaxe, tier: 3, drop: 'raw_gold'),
    BlockDef('diamond_ore', 'Diamond Ore', 0.50, 0.85, 0.85, hardness: 5.0, tool: ToolType.pickaxe, tier: 3, drop: 'diamond'),
    BlockDef('bedrock', 'Bedrock', 0.22, 0.22, 0.24, hardness: -1, drop: '-'),
    BlockDef('oak_planks', 'Oak Planks', 0.72, 0.56, 0.33, hardness: 2.0, tool: ToolType.axe),
    BlockDef('cobblestone', 'Cobblestone', 0.44, 0.44, 0.45, hardness: 3.0, tool: ToolType.pickaxe, tier: 1),
    BlockDef('lamp', 'Lamp', 0.98, 0.88, 0.50, hardness: 0.5, light: 15),
    BlockDef('crafting_table', 'Crafting Table', 0.62, 0.44, 0.24, hardness: 2.5, tool: ToolType.axe),
    BlockDef('glass', 'Glass', 0.80, 0.92, 0.97, a: 0.35, opaque: false, hardness: 0.4, drop: '-'),
    BlockDef('bricks', 'Bricks', 0.66, 0.31, 0.26, hardness: 3.0, tool: ToolType.pickaxe, tier: 1),
    BlockDef('stone_bricks', 'Stone Bricks', 0.47, 0.47, 0.50, hardness: 3.0, tool: ToolType.pickaxe, tier: 1),
    BlockDef('mossy_stone_bricks', 'Mossy Stone Bricks', 0.40, 0.50, 0.40, hardness: 3.0, tool: ToolType.pickaxe, tier: 1),
    BlockDef('tall_grass', 'Tall Grass', 0.40, 0.68, 0.28, shape: BlockShape.cross, solid: false, opaque: false, hardness: 0.0, drop: '-'),
    BlockDef('flower_red', 'Red Flower', 0.88, 0.24, 0.24, shape: BlockShape.flower, solid: false, opaque: false, hardness: 0.0),
    BlockDef('flower_yellow', 'Yellow Flower', 0.94, 0.84, 0.26, shape: BlockShape.flower, solid: false, opaque: false, hardness: 0.0),
    BlockDef('lava', 'Lava', 0.98, 0.45, 0.10, a: 0.92, shape: BlockShape.liquid, solid: false, opaque: false, hardness: -1, drop: '-', light: 13),
    BlockDef('clay', 'Clay', 0.62, 0.64, 0.70, hardness: 0.8, tool: ToolType.shovel),
    BlockDef('torch', 'Torch', 0.98, 0.78, 0.35, shape: BlockShape.torch, solid: false, opaque: false, hardness: 0.0, light: 13),
    BlockDef('chest', 'Chest', 0.58, 0.40, 0.20, hardness: 2.5, tool: ToolType.axe),
    BlockDef('furnace', 'Furnace', 0.38, 0.38, 0.41, hardness: 3.5, tool: ToolType.pickaxe, tier: 1),
    BlockDef('wool', 'Wool', 0.93, 0.93, 0.92, hardness: 0.8),
    BlockDef('spruce_planks', 'Spruce Planks', 0.50, 0.36, 0.22, hardness: 2.0, tool: ToolType.axe),
    BlockDef('dead_bush', 'Dead Bush', 0.55, 0.42, 0.24, shape: BlockShape.cross, solid: false, opaque: false, hardness: 0.0, drop: 'stick'),
    BlockDef('mushroom', 'Mushroom', 0.75, 0.35, 0.30, shape: BlockShape.flower, solid: false, opaque: false, hardness: 0.0, light: 2),
    BlockDef('gold_block', 'Gold Block', 0.95, 0.80, 0.30, hardness: 4.0, tool: ToolType.pickaxe, tier: 3),
    BlockDef('iron_block', 'Iron Block', 0.82, 0.82, 0.84, hardness: 4.0, tool: ToolType.pickaxe, tier: 2),
    BlockDef('diamond_block', 'Diamond Block', 0.45, 0.90, 0.88, hardness: 5.0, tool: ToolType.pickaxe, tier: 3),
    BlockDef('ice', 'Ice', 0.70, 0.85, 0.98, a: 0.75, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: '-'),
    BlockDef('dark_stone', 'Dark Stone', 0.33, 0.33, 0.37, hardness: 4.0, tool: ToolType.pickaxe, tier: 1, drop: 'cobblestone'),
    BlockDef('bone_block', 'Bone Block', 0.88, 0.86, 0.76, hardness: 2.0, tool: ToolType.pickaxe, tier: 1),
    BlockDef('bed', 'Bed', 0.85, 0.25, 0.30, hardness: 0.5),
    BlockDef('wheat_0', 'Wheat Sprout', 0.45, 0.70, 0.30, shape: BlockShape.cross, solid: false, opaque: false, hardness: 0.0, drop: 'wheat_seeds'),
    BlockDef('wheat_1', 'Young Wheat', 0.60, 0.72, 0.30, shape: BlockShape.cross, solid: false, opaque: false, hardness: 0.0, drop: 'wheat_seeds'),
    BlockDef('wheat_2', 'Wheat', 0.85, 0.75, 0.30, shape: BlockShape.cross, solid: false, opaque: false, hardness: 0.0, drop: 'wheat'),
    BlockDef('farmland', 'Farmland', 0.40, 0.27, 0.16, hardness: 0.8, tool: ToolType.shovel, drop: 'dirt'),
    BlockDef('spawner', 'Monster Spawner', 0.20, 0.12, 0.28, hardness: 5.0, tool: ToolType.pickaxe, tier: 1, drop: 'magic_dust', light: 4),
    BlockDef('tnt', 'TNT', 0.85, 0.20, 0.15, hardness: 0.0),
    BlockDef('ladder', 'Ladder', 0.60, 0.45, 0.25, shape: BlockShape.ladder, solid: false, opaque: false, hardness: 0.4, tool: ToolType.axe),
    BlockDef('door_z', 'Door', 0.62, 0.45, 0.25, shape: BlockShape.panelZ, opaque: false, hardness: 1.0, tool: ToolType.axe, drop: 'door'),
    BlockDef('door_x', 'Door', 0.62, 0.45, 0.25, shape: BlockShape.panelX, opaque: false, hardness: 1.0, tool: ToolType.axe, drop: 'door'),
    BlockDef('door_z_open', 'Open Door', 0.62, 0.45, 0.25, shape: BlockShape.panelX, solid: false, opaque: false, hardness: 1.0, tool: ToolType.axe, drop: 'door'),
    BlockDef('door_x_open', 'Open Door', 0.62, 0.45, 0.25, shape: BlockShape.panelZ, solid: false, opaque: false, hardness: 1.0, tool: ToolType.axe, drop: 'door'),
    BlockDef('wall_torch', 'Wall Torch', 0.98, 0.78, 0.35, shape: BlockShape.wallTorch, solid: false, opaque: false, hardness: 0.0, drop: 'torch', light: 13),
    BlockDef('enchanting_table', 'Enchanting Table', 0.38, 0.18, 0.55, hardness: 3.0, tool: ToolType.pickaxe, tier: 1, light: 7),
    BlockDef('brewing_stand', 'Brewing Stand', 0.30, 0.22, 0.30, hardness: 2.0, tool: ToolType.pickaxe, light: 3),
    BlockDef('waypoint', 'Waypoint', 0.35, 0.75, 0.95, hardness: 3.0, tool: ToolType.pickaxe, tier: 1, light: 10),
    BlockDef('oak_slab', 'Oak Slab', 0.72, 0.56, 0.33, shape: BlockShape.slab, opaque: false, hardness: 2.0, tool: ToolType.axe),
    BlockDef('stone_slab', 'Stone Slab', 0.50, 0.50, 0.52, shape: BlockShape.slab, opaque: false, hardness: 2.0, tool: ToolType.pickaxe, tier: 1),
    BlockDef('cobblestone_slab', 'Cobblestone Slab', 0.44, 0.44, 0.45, shape: BlockShape.slab, opaque: false, hardness: 2.0, tool: ToolType.pickaxe, tier: 1),
    BlockDef('oak_fence', 'Oak Fence', 0.43, 0.30, 0.17, shape: BlockShape.fence, opaque: false, hardness: 2.0, tool: ToolType.axe),
    BlockDef('oak_stairs_n', 'Oak Stairs', 0.72, 0.56, 0.33, shape: BlockShape.stairsN, opaque: false, hardness: 2.0, tool: ToolType.axe, drop: 'oak_stairs'),
    BlockDef('oak_stairs_e', 'Oak Stairs', 0.72, 0.56, 0.33, shape: BlockShape.stairsE, opaque: false, hardness: 2.0, tool: ToolType.axe, drop: 'oak_stairs'),
    BlockDef('oak_stairs_s', 'Oak Stairs', 0.72, 0.56, 0.33, shape: BlockShape.stairsS, opaque: false, hardness: 2.0, tool: ToolType.axe, drop: 'oak_stairs'),
    BlockDef('oak_stairs_w', 'Oak Stairs', 0.72, 0.56, 0.33, shape: BlockShape.stairsW, opaque: false, hardness: 2.0, tool: ToolType.axe, drop: 'oak_stairs'),
    BlockDef('stone_stairs_n', 'Stone Stairs', 0.50, 0.50, 0.52, shape: BlockShape.stairsN, opaque: false, hardness: 2.0, tool: ToolType.pickaxe, tier: 1, drop: 'stone_stairs'),
    BlockDef('stone_stairs_e', 'Stone Stairs', 0.50, 0.50, 0.52, shape: BlockShape.stairsE, opaque: false, hardness: 2.0, tool: ToolType.pickaxe, tier: 1, drop: 'stone_stairs'),
    BlockDef('stone_stairs_s', 'Stone Stairs', 0.50, 0.50, 0.52, shape: BlockShape.stairsS, opaque: false, hardness: 2.0, tool: ToolType.pickaxe, tier: 1, drop: 'stone_stairs'),
    BlockDef('stone_stairs_w', 'Stone Stairs', 0.50, 0.50, 0.52, shape: BlockShape.stairsW, opaque: false, hardness: 2.0, tool: ToolType.pickaxe, tier: 1, drop: 'stone_stairs'),
    // Stage 22: the FLOWING form of each liquid. `water` / `lava` stay the
    // infinite sources a bucket scoops; a `*_flow` cell is what the source
    // spreads into and drains when its feeder goes. One flowing id per liquid,
    // no levels.
    BlockDef('water_flow', 'Water', 0.26, 0.48, 0.82, a: 0.58, shape: BlockShape.liquid, solid: false, opaque: false, hardness: -1, drop: '-'),
    BlockDef('lava_flow', 'Lava', 0.99, 0.55, 0.16, a: 0.92, shape: BlockShape.liquid, solid: false, opaque: false, hardness: -1, drop: '-', light: 13),
    // Stage 23: the temple trap. A dark half-block on the chamber floor; a body
    // whose feet enter its cell lights the TNT the generator buried underneath
    // (`Game._checkPlateUnder`).
    BlockDef('pressure_plate', 'Pressure Plate', 0.24, 0.20, 0.18, shape: BlockShape.slab, opaque: false, hardness: 1.0, tool: ToolType.pickaxe),
    // Stage 26: the swamp (mud patches, reeds on the pool edges) and the jungle
    // (tall jungle logs, vines hanging under the canopy, ferns, melons that drop
    // slices).
    BlockDef('mud', 'Mud', 0.36, 0.26, 0.18, hardness: 0.8, tool: ToolType.shovel),
    BlockDef('reeds', 'Reeds', 0.55, 0.72, 0.38, shape: BlockShape.cross, solid: false, opaque: false, hardness: 0.0),
    BlockDef('jungle_log', 'Jungle Log', 0.42, 0.30, 0.16, hardness: 2.0, tool: ToolType.axe),
    BlockDef('vines', 'Vines', 0.22, 0.48, 0.20, shape: BlockShape.cross, solid: false, opaque: false, hardness: 0.0, drop: '-'),
    BlockDef('fern', 'Fern', 0.30, 0.60, 0.26, shape: BlockShape.cross, solid: false, opaque: false, hardness: 0.0, drop: '-'),
    BlockDef('melon', 'Melon', 0.45, 0.68, 0.25, hardness: 1.0, tool: ToolType.axe, drop: 'melon_slice'),
    // Stage 27: redstone-lite. Every powered / unpowered state is its own block
    // id, so a flip is a plain `setBlock` (meshed, saved and replicated like any
    // edit). The lever and the button borrow the torch geometry (top face = the
    // block colour), the wire is a 1/8 slab, the iron door mirrors the wooden
    // one (2 tall, `_z` / `_x` by facing, `_open` non-solid), the piston has
    // four facings and an `_on` twin of each.
    BlockDef('redstone_ore', 'Redstone Ore', 0.62, 0.30, 0.30, hardness: 4.0, tool: ToolType.pickaxe, tier: 2, drop: 'redstone_dust'),
    BlockDef('lever_off', 'Lever', 0.55, 0.55, 0.57, shape: BlockShape.torch, solid: false, opaque: false, hardness: 0.3, drop: 'lever'),
    BlockDef('lever_on', 'Lever', 0.95, 0.25, 0.20, shape: BlockShape.torch, solid: false, opaque: false, hardness: 0.3, drop: 'lever'),
    BlockDef('button', 'Button', 0.66, 0.66, 0.68, shape: BlockShape.torch, solid: false, opaque: false, hardness: 0.3, drop: 'button'),
    BlockDef('button_on', 'Button', 0.90, 0.90, 0.92, shape: BlockShape.torch, solid: false, opaque: false, hardness: 0.3, drop: 'button'),
    BlockDef('wire_off', 'Redstone Wire', 0.45, 0.10, 0.10, shape: BlockShape.wire, solid: false, opaque: false, hardness: 0.0, drop: 'wire'),
    BlockDef('wire_on', 'Redstone Wire', 1.00, 0.25, 0.20, shape: BlockShape.wire, solid: false, opaque: false, hardness: 0.0, drop: 'wire', light: 3),
    BlockDef('redstone_lamp_off', 'Redstone Lamp', 0.45, 0.32, 0.22, hardness: 0.5, drop: 'redstone_lamp'),
    BlockDef('redstone_lamp_on', 'Redstone Lamp', 1.00, 0.85, 0.45, hardness: 0.5, drop: 'redstone_lamp', light: 14),
    BlockDef('iron_door_z', 'Iron Door', 0.80, 0.80, 0.83, shape: BlockShape.panelZ, opaque: false, hardness: 4.0, tool: ToolType.pickaxe, tier: 1, drop: 'iron_door'),
    BlockDef('iron_door_x', 'Iron Door', 0.80, 0.80, 0.83, shape: BlockShape.panelX, opaque: false, hardness: 4.0, tool: ToolType.pickaxe, tier: 1, drop: 'iron_door'),
    BlockDef('iron_door_z_open', 'Open Iron Door', 0.80, 0.80, 0.83, shape: BlockShape.panelX, solid: false, opaque: false, hardness: 4.0, tool: ToolType.pickaxe, tier: 1, drop: 'iron_door'),
    BlockDef('iron_door_x_open', 'Open Iron Door', 0.80, 0.80, 0.83, shape: BlockShape.panelZ, solid: false, opaque: false, hardness: 4.0, tool: ToolType.pickaxe, tier: 1, drop: 'iron_door'),
    BlockDef('piston_n', 'Piston', 0.62, 0.50, 0.34, hardness: 1.5, tool: ToolType.pickaxe, drop: 'piston'),
    BlockDef('piston_e', 'Piston', 0.62, 0.50, 0.34, hardness: 1.5, tool: ToolType.pickaxe, drop: 'piston'),
    BlockDef('piston_s', 'Piston', 0.62, 0.50, 0.34, hardness: 1.5, tool: ToolType.pickaxe, drop: 'piston'),
    BlockDef('piston_w', 'Piston', 0.62, 0.50, 0.34, hardness: 1.5, tool: ToolType.pickaxe, drop: 'piston'),
    BlockDef('piston_n_on', 'Piston', 0.50, 0.50, 0.53, hardness: 1.5, tool: ToolType.pickaxe, drop: 'piston'),
    BlockDef('piston_e_on', 'Piston', 0.50, 0.50, 0.53, hardness: 1.5, tool: ToolType.pickaxe, drop: 'piston'),
    BlockDef('piston_s_on', 'Piston', 0.50, 0.50, 0.53, hardness: 1.5, tool: ToolType.pickaxe, drop: 'piston'),
    BlockDef('piston_w_on', 'Piston', 0.50, 0.50, 0.53, hardness: 1.5, tool: ToolType.pickaxe, drop: 'piston'),
    // Stage 28: rails. One block id per orientation (two straights, four curves,
    // four slopes) behind one `rail` item; `Rails.orient` picks the id from the
    // neighbours. A powered rail is straight only and has an `_on` twin the
    // circuit tick flips. Every rail is a thin non-solid block that needs a
    // solid below, like a wire.
    BlockDef('rail_ns', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railNs, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('rail_ew', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railEw, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('rail_ne', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railNe, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('rail_nw', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railNw, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('rail_se', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railSe, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('rail_sw', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railSw, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('rail_slope_n', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railSlopeN, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('rail_slope_e', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railSlopeE, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('rail_slope_s', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railSlopeS, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('rail_slope_w', 'Rail', 0.60, 0.60, 0.64, shape: BlockShape.railSlopeW, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'rail'),
    BlockDef('powered_rail_ns', 'Powered Rail', 0.70, 0.58, 0.28, shape: BlockShape.railNs, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'powered_rail'),
    BlockDef('powered_rail_ew', 'Powered Rail', 0.70, 0.58, 0.28, shape: BlockShape.railEw, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'powered_rail'),
    BlockDef('powered_rail_ns_on', 'Powered Rail', 1.00, 0.55, 0.25, shape: BlockShape.railNs, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'powered_rail', light: 4),
    BlockDef('powered_rail_ew_on', 'Powered Rail', 1.00, 0.55, 0.25, shape: BlockShape.railEw, solid: false, opaque: false, hardness: 0.5, tool: ToolType.pickaxe, drop: 'powered_rail', light: 4),
    // Stage 29: the underworld. Obsidian is what a lava SOURCE becomes under
    // water (a diamond pickaxe mines it) and the portal frame; `portal` is the lit
    // inside of that frame (non-solid, translucent, never an item); hellstone is
    // the underworld's rock, soul sand halves a walker's speed (`speedMult`, read
    // by the player and the mobs), glowstone lights the ceilings and drops dust,
    // quartz ore veins the walls, nether brick is the fortress, and the fortress
    // core holds the underworld heart (breakable once the Underworld Lord is dead).
    BlockDef('obsidian', 'Obsidian', 0.10, 0.06, 0.16, hardness: 15.0, tool: ToolType.pickaxe, tier: 4),
    BlockDef('portal', 'Portal', 0.55, 0.15, 0.95, a: 0.62, solid: false, opaque: false, hardness: -1, drop: '-', light: 11),
    BlockDef('hellstone', 'Hellstone', 0.42, 0.14, 0.12, hardness: 0.4, tool: ToolType.pickaxe, tier: 1),
    BlockDef('soul_sand', 'Soul Sand', 0.32, 0.24, 0.18, hardness: 0.5, tool: ToolType.shovel, speedMult: 0.5),
    BlockDef('glowstone', 'Glowstone', 0.98, 0.85, 0.45, hardness: 0.3, drop: 'glowstone_dust', light: 15),
    BlockDef('nether_quartz_ore', 'Quartz Ore', 0.62, 0.36, 0.34, hardness: 3.0, tool: ToolType.pickaxe, tier: 1, drop: 'quartz'),
    BlockDef('nether_brick', 'Nether Brick', 0.20, 0.09, 0.11, hardness: 2.0, tool: ToolType.pickaxe, tier: 1),
    BlockDef('fortress_core', 'Fortress Core', 0.45, 0.10, 0.70, hardness: 5.0, tool: ToolType.pickaxe, tier: 1, drop: 'underworld_heart', light: 8),
  ];

  /// VK3.1: the rows as voxel_content's registry — the numbering, the engine
  /// table, drops, liquids and lookups by id all come from it. The rows keep
  /// what is only this game's (the [ToolType] enum, the `''` / `'-'` drop
  /// spelling), translated here once.
  static final BlockRegistry<BlockType> registry = BlockRegistry([
    for (final d in defs)
      BlockType.rgb(
        d.id,
        d.r,
        d.g,
        d.b,
        name: d.name,
        alpha: d.a,
        shape: d.shape,
        solid: d.solid,
        opaque: d.opaque,
        hardness: d.hardness,
        tool: d.tool == ToolType.none ? null : d.tool.name,
        tier: d.tier,
        drop: switch (d.drop) { '' => null, '-' => '', final other => other },
        light: d.light,
        speed: d.speedMult,
        liquid: d.shape == BlockShape.liquid ? (d.id.endsWith('_flow') ? d.id.substring(0, d.id.length - 5) : d.id) : null,
        liquidSource: !d.id.endsWith('_flow'),
      ),
  ]);

  static const CollisionBox fullBox = CollisionBox.full;

  /// A lone post; a joined fence adds arms (voxel_core's `collisionBoxesAt`).
  static const CollisionBox fenceBox = CollisionBox.fencePost;

  /// Per block, the boxes a body collides with (voxel_core's `collisionBoxesOf`).
  static final List<List<CollisionBox>> _boxes = [
    for (final d in defs) collisionBoxesOf(d.shape, solid: d.solid),
  ];

  /// Shared, never mutate.
  static List<CollisionBox> collisionBoxes(int index) => _boxes[index];

  /// "water" / "lava" for a source OR its flowing form, "" for anything else.
  static String liquidKind(int index) => registry.liquidOf(index) ?? '';

  static bool isLiquidSource(int index) => table.isLiquidSource(index);

  /// The flowing form of a liquid kind ("water" -> water_flow).
  static int flowOf(String kind) => registry.flowingOf(kind);

  static int get count => registry.count;

  static int indexOf(String id) => registry.indexOf(id);

  static bool has(String id) => registry.has(id);
  static BlockDef def(int index) => defs[index];
  static String idOf(int index) => defs[index].id;
  static String displayName(int index) => defs[index].name;
  static bool isSolid(int index) => defs[index].solid;
  static bool isLiquid(int index) => defs[index].shape == BlockShape.liquid;
  static bool isOpaque(int index) => defs[index].opaque;
  static BlockShape shapeOf(int index) => defs[index].shape;
  static bool isPlant(int index) =>
      defs[index].shape == BlockShape.cross || defs[index].shape == BlockShape.flower;

  /// A block another block may be placed INTO: air, plants, liquids.
  static bool isReplaceable(int index) => registry.isReplaceable(index);

  static double hardness(int index) => defs[index].hardness;
  static ToolType toolOf(int index) => defs[index].tool;
  static int minTier(int index) => defs[index].tier;

  /// The item dropped when broken: "" means nothing.
  static String dropOf(int index) => registry.dropOf(index);

  static int lightOf(int index) => defs[index].light;

  /// Stage 29: how a block under a walker's feet scales its speed (soul sand: 0.5).
  static double speedMult(int index) => defs[index].speedMult;

  /// VK1.3: this game's say in voxel_core's [Pathfinder]: lava is never
  /// entered, a slow floor costs its inverse speed (soul sand 2).
  static final PathCosts pathCosts = registry.pathCosts(avoidLiquids: const {'lava'});

  /// Stage 32: the material family a block sounds like: "stone", "wood",
  /// "earth", "metal", "glass", "plant" or "liquid" (`Sfx` has a break / place /
  /// step voice for each), read from the id, first match in this order.
  /// Anything not named is stone.
  static const List<String> familyMetal = ['iron_', 'gold_block', 'diamond_block', 'rail', 'piston', 'furnace', 'brewing_stand', 'spawner', 'wire', 'redstone_lamp'];
  static const List<String> familyGlass = ['glass', 'ice', 'glowstone', 'portal', 'enchanting_table', 'lamp'];
  static const List<String> familyStone = ['stone', 'brick', 'ore', 'obsidian', 'bedrock', 'bone_block', 'fortress_core'];
  static const List<String> familyPlant = ['leaves', 'tall_grass', 'flower_', 'cactus', 'reeds', 'vines', 'fern', 'melon', 'wheat_', 'mushroom', 'dead_bush', 'wool', 'torch'];
  static const List<String> familyWood = ['log', 'planks', 'fence', 'oak_stairs', 'oak_slab', 'door_', 'chest', 'crafting_table', 'ladder', 'bed', 'waypoint', 'lever', 'button', 'pressure_plate'];
  static const List<String> familyEarth = ['dirt', 'grass', 'sand', 'gravel', 'snow', 'clay', 'mud', 'farmland'];
  static const List<List<String>> familyOrder = [familyMetal, familyGlass, familyStone, familyPlant, familyWood, familyEarth];
  static const List<String> familyNames = ['metal', 'glass', 'stone', 'plant', 'wood', 'earth'];

  static String materialFamily(int index) {
    if (isLiquid(index)) return 'liquid';
    final id = idOf(index);
    for (var f = 0; f < familyOrder.length; f++) {
      for (final k in familyOrder[f]) {
        if (id.contains(k)) return familyNames[f];
      }
    }
    return 'stone';
  }

  static bool isStairs(int index) {
    final sh = defs[index].shape;
    return sh.index >= BlockShape.stairsN.index && sh.index <= BlockShape.stairsW.index;
  }

  /// The orientation of a stairs block whose HIGH step sits at the back, along
  /// [forwardX]/[forwardZ] (the direction the placer looks). [index] is any of
  /// the four orientations of one stairs.
  static int stairsFacing(int index, double forwardX, double forwardZ) {
    if (!isStairs(index)) throw ArgumentError('not a stairs block: ${idOf(index)}');
    final id = idOf(index);
    final base = id.substring(0, id.length - 2);
    return indexOf(base + facingSuffix(forwardX, forwardZ));
  }

  /// "_n" / "_e" / "_s" / "_w": the compass side the forward vector points to
  /// (the way the placer looks).
  static String facingSuffix(double forwardX, double forwardZ) {
    if (forwardX.abs() > forwardZ.abs()) return forwardX > 0 ? '_e' : '_w';
    return forwardZ > 0 ? '_s' : '_n';
  }

  /// The unit step a compass suffix names.
  static IVec3 facingDir(String suffix) => switch (suffix) {
        '_n' => const IVec3(0, 0, -1),
        '_s' => const IVec3(0, 0, 1),
        '_e' => const IVec3(1, 0, 0),
        _ => const IVec3(-1, 0, 0),
      };

  // --- stage 27: circuit blocks ------------------------------------------------

  static bool isWire(int index) => defs[index].shape == BlockShape.wire;
  static bool isPiston(int index) => defs[index].id.startsWith('piston_');
  static bool isIronDoor(int index) => defs[index].id.startsWith('iron_door_');

  /// The piston facing the forward vector (retracted).
  static int pistonFacing(int index, double forwardX, double forwardZ) {
    if (!isPiston(index)) throw ArgumentError('not a piston: ${idOf(index)}');
    return indexOf('piston${facingSuffix(forwardX, forwardZ)}');
  }

  /// The direction a piston pushes: its `_n/_e/_s/_w` suffix, with or without `_on`.
  static IVec3 pistonDir(int index) {
    var id = idOf(index);
    if (id.endsWith('_on')) id = id.substring(0, id.length - 3);
    return facingDir(id.substring(id.length - 2));
  }

  // --- stage 28: rails ----------------------------------------------------------

  static bool isRail(int index) {
    final sh = defs[index].shape.index;
    return sh >= BlockShape.railNs.index && sh <= BlockShape.railSlopeW.index;
  }

  static bool isPoweredRail(int index) => defs[index].id.startsWith('powered_rail_');

  static bool isRailSlope(int index) {
    final sh = defs[index].shape.index;
    return sh >= BlockShape.railSlopeN.index && sh <= BlockShape.railSlopeW.index;
  }

  // --- tables handed to the mesher isolate ------------------------------------

  /// The liquid kinds, in the order voxel_core indexes them. A source and its
  /// `_flow` form share a kind.
  static List<String> get liquidKinds => registry.liquidKinds;

  /// The engine's view of this table (VP1.4; VK3.1: projected by [registry]).
  static VoxelBlockTable get table => registry.table;

  static Float32List palette() => table.palette;

  static Uint8List shapes() => table.shapes;

  static Uint8List opaqueTable() => table.opaque;

  static Uint8List emission() => table.emission;

  /// Every block id the generator needs, resolved once so the generator never
  /// spells a byte.
  static Map<String, int> generatorIds() => {
        for (final id in const [
          'stone', 'dirt', 'grass', 'sand', 'water', 'oak_log', 'oak_leaves', 'gravel',
          'sandstone', 'snow', 'spruce_log', 'spruce_leaves', 'cactus', 'coal_ore', 'iron_ore',
          'gold_ore', 'diamond_ore', 'bedrock', 'tall_grass', 'flower_red', 'flower_yellow', 'lava',
          'clay', 'dead_bush', 'mushroom', 'ice', 'dark_stone', 'mossy_stone_bricks', 'stone_bricks',
          'chest', 'lamp', 'bone_block', 'oak_planks', 'ladder', 'spawner', 'glass',
          'crafting_table', 'furnace', 'torch', 'oak_fence', 'tnt', 'cobblestone', 'pressure_plate',
          'mud', 'reeds', 'jungle_log', 'vines', 'fern', 'melon', 'bed', 'farmland', 'wheat_2', 'oak_slab',
          'redstone_ore', 'rail_ew',
          'hellstone', 'soul_sand', 'glowstone', 'nether_quartz_ore', 'nether_brick', 'fortress_core',
        ])
          id: indexOf(id),
      };
}
