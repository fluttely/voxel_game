import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/core/items.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/core/recipes.dart';
import 'package:voxel_game_minecraft/src/core/species.dart';
import 'package:voxel_game_minecraft/src/game/achievements.dart';
import 'package:voxel_game_minecraft/src/game/effects.dart';
import 'package:voxel_game_minecraft/src/game/loot.dart';
import 'package:voxel_game_minecraft/src/game/music.dart';
import 'package:voxel_game_minecraft/src/game/portals.dart';
import 'package:voxel_game_minecraft/src/world/terrain_generator.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 29's headless proofs (Godot `--stage29` covers the rest in the app):
/// the appended underworld blocks, the underworld generator (bedrock floor and
/// roof, the lava sea, the census), the seed 42 fortress Godot found, the
/// portal frame, the arrival spot, and the version-2 save with a delta per
/// dimension.
void main() {
  int id(String s) => Blocks.indexOf(s);
  const floorY = 10;

  VoxelWorld flatWorld() {
    final w = VoxelWorld(seedValue: 42, loadRadius: 1);
    final c = Uint8List(VoxelWorld.volume);
    for (var i = 0; i < 16 * 16 * floorY; i++) {
      c[i] = id('stone');
    }
    w.chunks[(x: 0, z: 0)] = c;
    return w;
  }

  test('8 underworld blocks appended after the rails, in Godot order; items, recipes, species, tables', () {
    const order = [
      'obsidian', 'portal', 'hellstone', 'soul_sand', 'glowstone', 'nether_quartz_ore', 'nether_brick', 'fortress_core',
    ];
    final last = id('powered_rail_ew_on');
    for (var i = 0; i < order.length; i++) {
      expect(id(order[i]), last + 1 + i, reason: order[i]);
    }
    expect(Blocks.count, last + 1 + order.length);
    expect(Blocks.speedMult(id('soul_sand')), 0.5);
    expect(Blocks.speedMult(id('hellstone')), 1.0);
    expect(Blocks.isSolid(id('portal')), isFalse);
    expect(Blocks.lightOf(id('portal')), 11);
    expect(Blocks.lightOf(id('glowstone')), 15);
    expect(Blocks.lightOf(id('fortress_core')), 8);
    expect(Blocks.minTier(id('obsidian')), 4);
    expect(Blocks.dropOf(id('glowstone')), 'glowstone_dust');
    expect(Blocks.dropOf(id('nether_quartz_ore')), 'quartz');
    expect(Blocks.dropOf(id('fortress_core')), 'underworld_heart');
    for (final g in ['hellstone', 'soul_sand', 'glowstone', 'nether_quartz_ore', 'nether_brick', 'fortress_core']) {
      expect(Blocks.generatorIds()[g], id(g), reason: g);
    }
    expect(Items.has('portal'), isFalse);
    expect(Items.has('obsidian'), isTrue);
    expect(Items.kind('flint_and_steel'), ItemKind.equipment);
    for (final m in ['glowstone_dust', 'quartz', 'blaze_rod', 'underworld_heart']) {
      expect(Items.kind(m), ItemKind.material, reason: m);
    }
    expect(Recipes.list.firstWhere((r) => r.result == 'flint_and_steel').ingredients, {'iron_ingot': 1, 'flint': 1});
    expect(Recipes.list.firstWhere((r) => r.result == 'glowstone').ingredients, {'glowstone_dust': 4});
    for (final sp in ['blaze', 'dark_skeleton', 'magma_cube']) {
      expect(Species.def(sp).biomes, [9], reason: sp);
    }
    expect(Species.def('underworld_lord').boss, isTrue);
    expect(Species.def('underworld_lord').hp, 200);
    expect(Species.def('underworld_lord').volley, 5);
    expect(Species.def('blaze').projectile, 'fire');
    expect(StatusEffects.def('wither').period, 1.5);
    expect(LootTables.tableByKind[9], 'fortress');
    expect(LootTables.tables['fortress']!.first.item, 'quartz');
    expect(Achievements.def('underworld').name, 'Into the Fire');
    expect(Achievements.def('heart').name, 'Heart of the Underworld');
    expect(Music.moodFor(9, true, false, true), 'Underworld');
    expect(Music.trackFor('Underworld'), 'nighttime_fireflies.ogg');
  });

  test('the underworld chunk: bedrock floor y 7 and roof y 100, lava only at y <= 28, nothing above the roof', () {
    final gen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 42);
    expect(gen.biomeAt(0, 0) != TerrainGenerator.biomeUnderworld, isTrue);
    gen.setDimension(TerrainGenerator.dimUnderworld);
    expect(gen.biomeAt(0, 0), TerrainGenerator.biomeUnderworld);
    gen.setDimension(TerrainGenerator.dimOverworld);
    final over = gen.generate(1, 0);
    expect(gen.generateIn(1, 0, TerrainGenerator.dimOverworld), over);
    final b = gen.generateIn(1, 0, TerrainGenerator.dimUnderworld);
    var lavaHigh = 0, open = 0, water = 0;
    for (var z = 0; z < 16; z++) {
      for (var x = 0; x < 16; x++) {
        for (final y in const [0, 7, 100]) {
          expect(b[TerrainGenerator.index(x, y, z)], id('bedrock'), reason: '($x,$y,$z)');
        }
        for (var y = 101; y < 128; y++) {
          expect(b[TerrainGenerator.index(x, y, z)], Blocks.air);
        }
        for (var y = 8; y < 100; y++) {
          final v = b[TerrainGenerator.index(x, y, z)];
          if (v == id('lava') && y > 28) lavaHigh++;
          if (v == Blocks.air || v == id('lava')) open++;
          if (v == id('water')) water++;
        }
      }
    }
    expect(lavaHigh, 0);
    expect(water, 0);
    final share = open / (16 * 16 * 92);
    expect(share > 0.2 && share < 0.6, isTrue, reason: 'open share $share');
  });

  test('census over the 5x5 chunks around Godot\'s arrival column (19, 11), seed 42', () {
    final gen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 42);
    final counts = <String, int>{'hellstone': 0, 'lava': 0, 'glowstone': 0, 'nether_quartz_ore': 0, 'soul_sand': 0};
    for (var cz = -2; cz < 3; cz++) {
      for (var cx = -1; cx < 4; cx++) {
        for (final v in gen.generateIn(cx, cz, TerrainGenerator.dimUnderworld)) {
          final name = Blocks.idOf(v);
          if (counts.containsKey(name)) counts[name] = counts[name]! + 1;
        }
      }
    }
    // Godot (generator + the probe's few edits): hellstone 378100, lava 43743,
    // glowstone 1604, quartz 13947, soul sand 2450.
    // ignore: avoid_print
    print('stage29 census $counts');
    for (final e in counts.entries) {
      expect(e.value > 0, isTrue, reason: e.key);
    }
  });

  test('seed 42 has the fortress Godot found at (34, 27): layout, bricks, chests, core', () {
    final gen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 42);
    final near = gen.structuresNearIn(2, 1, TerrainGenerator.dimUnderworld);
    final f = near.firstWhere((s) => s.x == 34 && s.z == 27);
    expect(f.type, TerrainGenerator.structFortress);
    expect(gen.structuresNearIn(2, 1, TerrainGenerator.dimOverworld).any((s) => s.type == TerrainGenerator.structFortress), isFalse);
    final layout = gen.fortressLayout(f.x, f.y, f.z);
    expect(layout.length >= 40 && layout.length <= 60, isTrue);
    expect(layout.core, IVec3(f.x + layout.length + 5, f.y, f.z));
    final chunks = <({int x, int z}), Uint8List>{};
    int at(int x, int y, int z) {
      final c = (x: (x / 16).floor(), z: (z / 16).floor());
      final blocks = chunks[c] ??= gen.generateIn(c.x, c.z, TerrainGenerator.dimUnderworld);
      return blocks[TerrainGenerator.index(x - c.x * 16, y, z - c.z * 16)];
    }

    var bricks = 0;
    for (var x = f.x; x < f.x + layout.length + 11; x++) {
      for (var y = f.y; y < f.y + 9; y++) {
        for (var z = f.z - 5; z < f.z + 6; z++) {
          if (at(x, y, z) == id('nether_brick')) bricks++;
        }
      }
    }
    // ignore: avoid_print
    print('stage29 fortress origin (${f.x},${f.y},${f.z}) length ${layout.length} bricks $bricks');
    expect(bricks, 1557); // Godot's session log
    expect(at(layout.chestA.x, layout.chestA.y, layout.chestA.z), id('chest'));
    expect(at(layout.chestB.x, layout.chestB.y, layout.chestB.z), id('chest'));
    expect(at(layout.core.x, layout.core.y, layout.core.z), id('fortress_core'));
  });

  test('a 4x5 obsidian frame lights into six portal blocks in either plane; a broken frame does not', () {
    final w = flatWorld();
    final y = floorY;
    void frame(IVec3 cell, IVec3 axis) {
      for (var i = -1; i < 3; i++) {
        for (var j = -1; j < 4; j++) {
          final inside = i >= 0 && i <= 1 && j >= 0 && j <= 2;
          w.setBlock(IVec3(cell.x + axis.x * i, cell.y + j, cell.z + axis.z * i), inside ? Blocks.air : id('obsidian'));
        }
      }
    }

    frame(IVec3(4, y, 4), const IVec3(1, 0, 0));
    expect(Portals.light(w, IVec3(5, y + 2, 4)), 6); // the top-right cell of the hollow finds its corner
    expect(Portals.isPortal(w.getBlockXYZ(4, y, 4)), isTrue);
    expect(Portals.isPortal(w.getBlockXYZ(5, y + 2, 4)), isTrue);
    expect(Portals.light(w, IVec3(5, y + 1, 4)), 0); // already lit

    frame(IVec3(11, y, 3), const IVec3(0, 0, 1));
    expect(Portals.light(w, IVec3(11, y, 3)), 6);

    frame(IVec3(4, y, 11), const IVec3(1, 0, 0));
    w.setBlock(IVec3(6, y + 1, 11), Blocks.air); // a hole in the right side
    expect(Portals.light(w, IVec3(4, y, 11)), 0);

    expect(Portals.near(w, Vector3(5.5, y + 0.5, 8.5), 16), isNot(const IVec3(0, -1, 0)));
    expect(Portals.near(w, Vector3(5.5, y + 0.5, 8.5), 2).y, -1);
  });

  test('the return frame: built around its hollow with a floor in front; the arrival spot', () {
    final w = flatWorld();
    final cell = IVec3(6, floorY + 2, 6); // floating: the floor in front gets laid
    Portals.buildAt(w, cell);
    var portal = 0, obsidian = 0;
    for (var dx = -1; dx < 3; dx++) {
      for (var dy = -1; dy < 4; dy++) {
        final v = w.getBlock(cell + IVec3(dx, dy, 0));
        if (v == id('portal')) portal++;
        if (v == id('obsidian')) obsidian++;
      }
    }
    expect(portal, 6);
    expect(obsidian, 14);
    expect(Blocks.idOf(w.getBlock(cell + const IVec3(0, -1, 1))), 'cobblestone');
    expect(Portals.findSafeY(w, 2, 2, VoxelWorld.dimOverworld), floorY);
    // The underworld carves a pocket at 64 when nothing fits (the flat chunk is solid only below 10).
    expect(Portals.findSafeY(w, 2, 2, VoxelWorld.dimUnderworld), 64);
    expect(Blocks.idOf(w.getBlockXYZ(2, 63, 2)), 'hellstone');
  });

  test('blocks.bin version 2: a delta per dimension, storeEdit for the unloaded one, version 1 still loads', () {
    final w = flatWorld();
    w.setBlock(const IVec3(1, floorY, 1), id('glass'));
    w.setBlock(const IVec3(2, floorY, 1), id('glass'));
    expect(w.editCountIn(0), 2);
    w.switchDimension(VoxelWorld.dimUnderworld);
    expect(w.dimension, 1);
    expect(w.chunks, isEmpty);
    expect(w.generator.dimension, TerrainGenerator.dimUnderworld);
    w.chunks[(x: 0, z: 0)] = Uint8List(VoxelWorld.volume);
    w.setBlock(const IVec3(3, 40, 3), id('obsidian'));
    w.storeEdit(0, const IVec3(4, floorY, 4), id('portal')); // an overworld edit while in the underworld
    expect(w.editCountIn(0), 3);
    expect(w.editCountIn(1), 1);
    final bytes = w.editsToBytes();
    expect(ByteData.sublistView(bytes).getUint32(4, Endian.little), 2);

    final r = VoxelWorld(seedValue: 42, loadRadius: 1);
    expect(r.loadEditsFromBytes(bytes), 42);
    expect(r.editCountIn(0), 3);
    expect(r.editCountIn(1), 1);
    // The loaded dimension's delta lands on its generated chunk.
    r.switchDimension(1);
    expect(r.editCountIn(1), 1);
    expect(r.editCountIn(0), 3);

    // Version 1: magic, 1, seed, one delta -> dimension 0.
    final v1 = ByteData(4 + 4 + 8 + 4 + 8 + 8 + 4 + 5);
    var o = 0;
    v1.setUint32(o, VoxelWorld.saveMagic, Endian.little); o += 4;
    v1.setUint32(o, 1, Endian.little); o += 4;
    v1.setInt64(o, 7, Endian.little); o += 8;
    v1.setUint32(o, 1, Endian.little); o += 4;
    v1.setInt64(o, 0, Endian.little); o += 8;
    v1.setInt64(o, 0, Endian.little); o += 8;
    v1.setUint32(o, 1, Endian.little); o += 4;
    v1.setUint32(o, 17, Endian.little); o += 4;
    v1.setUint8(o, id('glass'));
    final old = VoxelWorld(seedValue: 7, loadRadius: 1);
    expect(old.loadEditsFromBytes(v1.buffer.asUint8List()), 7);
    expect(old.editCountIn(0), 1);
    expect(old.editCountIn(1), 0);
  });
}
