import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/spec/mob_table.dart';

import 'surface_area.dart';

/// The block table's order: a world's edits are kept by these indices, so a
/// block is appended here and at the table's end, never moved.
const List<String> _savedOrder = [
  'air', 'stone', 'dirt', 'grass', 'sand', 'water', 'oak_log', 'oak_leaves', 'gravel', 'sandstone', 'snow', //
  'spruce_log', 'spruce_leaves', 'cactus', 'coal_ore', 'iron_ore', 'gold_ore', 'diamond_ore', 'bedrock', //
  'oak_planks', 'cobblestone', 'lamp', 'crafting_table', 'glass', 'bricks', 'stone_bricks', //
  'mossy_stone_bricks', 'tall_grass', 'flower_red', 'flower_yellow', 'lava', 'clay', 'torch', 'chest', //
  'furnace', 'wool', 'spruce_planks', 'dead_bush', 'mushroom', 'gold_block', 'iron_block', 'diamond_block', //
  'ice', 'dark_stone', 'bone_block', 'bed', 'wheat_0', 'wheat_1', 'wheat_2', 'farmland', 'spawner', 'tnt', //
  'ladder', 'door_z', 'door_x', 'door_z_open', 'door_x_open', 'wall_torch', 'enchanting_table', //
  'brewing_stand', 'waypoint', 'oak_slab', 'stone_slab', 'cobblestone_slab', 'oak_fence', 'oak_stairs_n', //
  'oak_stairs_e', 'oak_stairs_s', 'oak_stairs_w', 'stone_stairs_n', 'stone_stairs_e', 'stone_stairs_s', //
  'stone_stairs_w', 'water_flow', 'lava_flow', 'pressure_plate', 'mud', 'reeds', 'jungle_log', 'vines', 'fern', //
  'melon', 'redstone_ore', 'lever_off', 'lever_on', 'button', 'button_on', 'wire_off', 'wire_on', //
  'redstone_lamp_off', 'redstone_lamp_on', 'iron_door_z', 'iron_door_x', 'iron_door_z_open', //
  'iron_door_x_open', 'piston_n', 'piston_e', 'piston_s', 'piston_w', 'piston_n_on', 'piston_e_on', //
  'piston_s_on', 'piston_w_on', 'rail_ns', 'rail_ew', 'rail_ne', 'rail_nw', 'rail_se', 'rail_sw', //
  'rail_slope_n', 'rail_slope_e', 'rail_slope_s', 'rail_slope_w', 'powered_rail_ns', 'powered_rail_ew', //
  'powered_rail_ns_on', 'powered_rail_ew_on', 'obsidian', 'portal', 'hellstone', 'soul_sand', 'glowstone', //
  'nether_quartz_ore', 'nether_brick', 'fortress_core', 'sealed_core',
];

void main() {
  final blocks = gameSpec.buildBlocks();
  final items = gameSpec.buildItems(blocks);
  final table = blocks.table;
  int id(String name) => blocks.indexOf(name);

  test('the block table is byte-sized, air is zero, and the order a save keeps is the order it was', () {
    expect(blocks.count <= 256, isTrue);
    expect(id('air'), 0);
    expect([for (var i = 0; i < blocks.count; i++) blocks[i].id], _savedOrder);
    expect(id('tall_grass'), 27);
    expect(blocks[id('tall_grass')].shape, BlockShape.cross);
  });

  test('items cover every block the bag shows and the recipes resolve', () {
    expect(items.has('oak_planks'), isTrue);
    expect(items.has('door'), isTrue);
    expect(items.has('door_x'), isFalse);
    for (final r in gameSpec.recipes) {
      expect(items.has(r.result), isTrue, reason: r.result);
      for (final k in r.ingredients.keys) {
        expect(items.has(k), isTrue, reason: k);
      }
    }
    expect(speciesTable, hasLength(29));
  });

  test('the generator fills a chunk with a surface and the mesher emits faces', () {
    final gen = gameSpec.world.compile({for (var i = 0; i < blocks.count; i++) blocks[i].id: i}, 1337);
    final chunk = gen.generateIn(0, 0, 0);
    expect(chunk.length, ChunkSize.volume);
    var solid = 0;
    for (final b in chunk) {
      if (b != 0) solid++;
    }
    expect(solid > 16 * 16 * 20, isTrue);
    final h = gen.surfaceHeight(8, 8);
    expect(h >= 6 && h <= 122, isTrue);
    final ring = [
      for (var dz = -1; dz <= 1; dz++)
        for (var dx = -1; dx <= 1; dx++) gen.generateIn(dx, dz, 0),
    ];
    // ring order in the world: c, nx, px, nz, pz, nxnz, pxnz, nxpz, pxpz
    Uint8List at(int dx, int dz) => ring[(dz + 1) * 3 + (dx + 1)];
    final r = table.mesher().build(0, 0, [
      at(0, 0),
      at(-1, 0),
      at(1, 0),
      at(0, -1),
      at(0, 1),
      at(-1, -1),
      at(1, -1),
      at(-1, 1),
      at(1, 1),
    ]);
    expect(r.faces > 200, isTrue);
    expect(r.solid.positions.length % 12, 0);
    expect(r.solid.colors.length, r.solid.vertexCount * 4);
    expect(r.solid.indices.length, r.solid.faceCount * 6);
    for (final i in r.solid.indices) {
      expect(i < r.solid.vertexCount, isTrue);
    }
  });

  test('a flat slab of stone with one tuft meshes into solid and cutout faces', () {
    final c = Uint8List(ChunkSize.volume);
    for (var i = 0; i < 16 * 16 * 40; i++) {
      c[i] = id('stone');
    }
    c[16 * 16 * 40 + 8 + 16 * 8] = id('tall_grass');
    final r = table.mesher().build(0, 0, [c, ...ChunkMesher.noNeighbours]);
    expect(r.cutout.faceCount, 4);
    // the top + the four open sides (neighbours are air when the ring is missing),
    // in square blocks: the mesher merges coplanar faces
    expect(surfaceArea(r.solid), 16 * 16 + 4 * 16 * 40);
  });

  test('slab, fence and stairs mesh as sub-block boxes', () {
    int facesOf(void Function(Uint8List c) place) {
      final c = Uint8List(ChunkSize.volume);
      place(c);
      return table.mesher().build(0, 0, [c, ...ChunkMesher.noNeighbours]).solid.faceCount;
    }

    int at(int x, int y, int z) => x + 16 * (z + 16 * y);

    // A slab floating in air: six boxes faces, none culled.
    expect(facesOf((c) => c[at(8, 40, 8)] = id('oak_slab')), 6);
    // A fence with no neighbour is a bare post: six faces, no rails.
    expect(facesOf((c) => c[at(8, 40, 8)] = id('oak_fence')), 6);
    // Two fences side by side: each is a post (6) plus two rails reaching the
    // neighbour. A rail's far face is flush with the block boundary and meets
    // the same block id, so it is culled: 5 faces per rail.
    expect(
      facesOf((c) {
        c[at(8, 40, 8)] = id('oak_fence');
        c[at(9, 40, 8)] = id('oak_fence');
      }),
      (6 + 5 * 2) * 2,
    );
    // Stairs: the bottom slab's six faces plus the step's five (its bottom face
    // is inside the block and skipped).
    expect(facesOf((c) => c[at(8, 40, 8)] = id('oak_stairs_n')), 11);
    // A slab sitting on stone loses its bottom face to the opaque neighbour;
    // the stone keeps all six, because a slab does not occlude.
    expect(
      facesOf((c) {
        c[at(8, 39, 8)] = id('stone');
        c[at(8, 40, 8)] = id('oak_slab');
      }),
      5 + 6,
    );
  });

  test('stairs face the way the placer looks, four blocks behind one item', () {
    final facing = blocks[id('oak_stairs_n')].facing!;
    expect(facing.toward(0, -1), 'oak_stairs_n');
    expect(facing.toward(0, 1), 'oak_stairs_s');
    expect(facing.toward(1, 0), 'oak_stairs_e');
    expect(facing.toward(-1, 0), 'oak_stairs_w');
    expect(items.has('oak_stairs'), isTrue);
    expect(items.has('oak_stairs_n'), isFalse);
    expect(items['oak_stairs'].block, 'oak_stairs_n');
    for (final turned in ['oak_stairs_e', 'oak_stairs_s', 'oak_stairs_w']) {
      expect(blocks.dropOf(id(turned)), 'oak_stairs');
    }
  });
}
