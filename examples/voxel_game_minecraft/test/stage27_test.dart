import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/core/items.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/core/recipes.dart';
import 'package:voxel_game_minecraft/src/world/terrain_generator.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage 27's headless proofs (Godot `--stage27` covers the rest in the app):
/// the appended circuit blocks, power through wires into lamps, doors, pistons
/// and TNT, the button timer, the wire's reach and the staircase rule, the WIRE
/// mesh and the glow surface, and the redstone ore band.
void main() {
  const floorY = 10; // stone fills y 0..9, circuits sit on y 10
  const dt = 1.0 / 60.0;
  int id(String s) => Blocks.indexOf(s);

  VoxelWorld flatWorld() {
    final w = VoxelWorld(seedValue: 42, loadRadius: 1);
    final c = Uint8List(VoxelWorld.volume);
    for (var i = 0; i < 16 * 16 * floorY; i++) {
      c[i] = id('stone');
    }
    w.chunks[(x: 0, z: 0)] = c;
    return w;
  }

  /// Simulation ticks at 60 Hz, the rate `Game` steps the circuits.
  void run(VoxelWorld w, double seconds) {
    for (var i = 0; i < (seconds / dt).round(); i++) {
      w.circuits.tick(dt);
    }
  }

  String at(VoxelWorld w, int x, int y, int z) => Blocks.idOf(w.getBlockXYZ(x, y, z));

  test('21 circuit blocks appended after the melon, in Godot order; items and recipes', () {
    const order = [
      'redstone_ore', 'lever_off', 'lever_on', 'button', 'button_on', 'wire_off', 'wire_on',
      'redstone_lamp_off', 'redstone_lamp_on', 'iron_door_z', 'iron_door_x', 'iron_door_z_open', 'iron_door_x_open',
      'piston_n', 'piston_e', 'piston_s', 'piston_w', 'piston_n_on', 'piston_e_on', 'piston_s_on', 'piston_w_on',
    ];
    final melon = id('melon');
    for (var i = 0; i < order.length; i++) {
      expect(id(order[i]), melon + 1 + i, reason: order[i]);
    }
    expect(id('rail_ns'), melon + 1 + order.length); // stage 28 appends after the pistons
    expect(Blocks.count <= 256, isTrue);
    expect(Blocks.shapeOf(id('wire_on')), BlockShape.wire);
    expect(Blocks.isSolid(id('wire_off')), isFalse);
    expect(Blocks.lightOf(id('redstone_lamp_on')), 14);
    expect(Blocks.isSolid(id('iron_door_x_open')), isFalse);
    expect(Blocks.shapeOf(id('iron_door_z_open')), BlockShape.panelX);
    expect(Blocks.dropOf(id('redstone_ore')), 'redstone_dust');
    expect(Blocks.dropOf(id('piston_w_on')), 'piston');
    expect(Blocks.pistonDir(id('piston_e_on')), const IVec3(1, 0, 0));
    expect(Blocks.pistonDir(id('piston_n')), const IVec3(0, 0, -1));
    expect(Blocks.pistonFacing(id('piston_n'), 0, 1), id('piston_s'));
    expect(Blocks.generatorIds()['redstone_ore'], id('redstone_ore'));
    for (final item in ['lever', 'button', 'wire', 'redstone_lamp', 'iron_door', 'piston', 'redstone_ore', 'redstone_dust']) {
      expect(Items.has(item), isTrue, reason: item);
    }
    for (final state in ['lever_on', 'wire_off', 'wire_on', 'piston_e', 'piston_n_on', 'iron_door_x', 'redstone_lamp_on']) {
      expect(Items.has(state), isFalse, reason: state);
    }
    expect(Items.blockOf('piston'), id('piston_n'));
    expect(Items.blockOf('wire'), id('wire_off'));
    final wire = Recipes.list.firstWhere((r) => r.result == 'wire');
    expect([wire.count, wire.ingredients['redstone_dust'], wire.station], [4, 1, '']);
    final piston = Recipes.list.firstWhere((r) => r.result == 'piston');
    expect(piston.ingredients, {'oak_planks': 3, 'cobblestone': 4, 'iron_ingot': 1, 'redstone_dust': 1});
  });

  test('lever -> five wires -> lamp lights and goes dark; strength drops one per cell', () {
    final w = flatWorld();
    w.setBlock(const IVec3(2, floorY, 8), id('lever_off'));
    for (var x = 3; x < 8; x++) {
      w.setBlock(IVec3(x, floorY, 8), id('wire_off'));
    }
    w.setBlock(const IVec3(8, floorY, 8), id('redstone_lamp_off'));
    run(w, 0.3);
    expect(at(w, 8, floorY, 8), 'redstone_lamp_off');
    expect(w.circuits.useBlock(const IVec3(2, floorY, 8)), isTrue);
    run(w, 0.2);
    expect(at(w, 8, floorY, 8), 'redstone_lamp_on');
    expect([for (var x = 3; x < 8; x++) w.circuits.strengthAt(IVec3(x, floorY, 8))], [15, 14, 13, 12, 11]);
    expect(at(w, 5, floorY, 8), 'wire_on');
    w.circuits.useBlock(const IVec3(2, floorY, 8));
    run(w, 0.2);
    expect(at(w, 8, floorY, 8), 'redstone_lamp_off');
    expect(at(w, 5, floorY, 8), 'wire_off');
    expect(w.circuits.strengthAt(const IVec3(3, floorY, 8)), 0);
  });

  test('a button powers for one second', () {
    final w = flatWorld();
    w.setBlock(const IVec3(2, floorY, 4), id('button'));
    for (var x = 3; x < 6; x++) {
      w.setBlock(IVec3(x, floorY, 4), id('wire_off'));
    }
    w.setBlock(const IVec3(6, floorY, 4), id('redstone_lamp_off'));
    run(w, 0.3);
    w.circuits.useBlock(const IVec3(2, floorY, 4));
    var onTick = -1, offTick = -1;
    for (var i = 1; i <= 180; i++) {
      w.circuits.tick(dt);
      final lit = at(w, 6, floorY, 4) == 'redstone_lamp_on';
      if (lit && onTick < 0) onTick = i;
      if (!lit && onTick >= 0) {
        offTick = i;
        break;
      }
    }
    expect(onTick, 1);
    expect(offTick * dt, closeTo(1.0, 0.05));
    expect(at(w, 2, floorY, 4), 'button');
  });

  test('a pressed plate powers the TNT under it and a lamp down its wire; leaving turns it off', () {
    final w = flatWorld();
    final lit = <IVec3>[];
    w.circuits.onTntPowered = lit.add;
    const plate = IVec3(4, floorY, 12);
    w.setBlock(plate + IVec3.down, id('tnt'));
    w.setBlock(plate, id('pressure_plate'));
    w.setBlock(const IVec3(5, floorY, 12), id('wire_off'));
    w.setBlock(const IVec3(6, floorY, 12), id('redstone_lamp_off'));
    run(w, 0.3);
    expect(lit, isEmpty);
    w.circuits.setPressedPlates({plate});
    w.circuits.tick(dt);
    expect(lit, [plate + IVec3.down]);
    expect(at(w, 6, floorY, 12), 'redstone_lamp_on');
    w.circuits.setPressedPlates({});
    run(w, 0.2);
    expect(at(w, 6, floorY, 12), 'redstone_lamp_off');
  });

  test('power reaches 15 cells, never the 16th', () {
    final w = flatWorld();
    // One chunk is 16 wide: fifteen wires along x, the sixteenth turns the corner.
    w.setBlock(const IVec3(0, floorY, 2), id('lever_on'));
    for (var x = 1; x <= 15; x++) {
      w.setBlock(IVec3(x, floorY, 2), id('wire_off'));
    }
    w.setBlock(const IVec3(15, floorY, 3), id('wire_off'));
    run(w, 0.2);
    expect(w.circuits.strengthAt(const IVec3(15, floorY, 2)), 1);
    expect(w.circuits.strengthAt(const IVec3(15, floorY, 3)), 0);
    expect(at(w, 15, floorY, 2), 'wire_on');
    expect(at(w, 15, floorY, 3), 'wire_off');
  });

  test('wires climb one step along a block edge unless a block caps the lower wire', () {
    final w = flatWorld();
    w.setBlock(const IVec3(2, floorY, 6), id('lever_on'));
    w.setBlock(const IVec3(3, floorY, 6), id('wire_off'));
    w.setBlock(const IVec3(4, floorY, 6), id('stone'));
    w.setBlock(const IVec3(4, floorY + 1, 6), id('wire_off'));
    run(w, 0.2);
    expect(w.circuits.strengthAt(const IVec3(4, floorY + 1, 6)), 14);
    // A cap over the lower wire cuts the climb.
    w.setBlock(const IVec3(3, floorY + 1, 6), id('stone'));
    run(w, 0.2);
    expect(w.circuits.strengthAt(const IVec3(3, floorY, 6)), 15);
    expect(w.circuits.strengthAt(const IVec3(4, floorY + 1, 6)), 0);
    expect(at(w, 4, floorY + 1, 6), 'wire_off');
  });

  test('an iron door opens both halves when powered and shuts again', () {
    final w = flatWorld();
    w.setBlock(const IVec3(2, floorY, 10), id('lever_off'));
    w.setBlock(const IVec3(3, floorY, 10), id('wire_off'));
    w.setBlock(const IVec3(4, floorY, 10), id('iron_door_x'));
    w.setBlock(const IVec3(4, floorY + 1, 10), id('iron_door_x'));
    run(w, 0.2);
    expect(at(w, 4, floorY, 10), 'iron_door_x');
    w.circuits.useBlock(const IVec3(2, floorY, 10));
    run(w, 0.2);
    expect(at(w, 4, floorY, 10), 'iron_door_x_open');
    expect(at(w, 4, floorY + 1, 10), 'iron_door_x_open');
    w.circuits.useBlock(const IVec3(2, floorY, 10));
    run(w, 0.2);
    expect(at(w, 4, floorY, 10), 'iron_door_x');
    expect(at(w, 4, floorY + 1, 10), 'iron_door_x');
  });

  test('a piston pushes the block in front one cell, stays blocked by a wall, keeps the block on retract', () {
    final w = flatWorld();
    const lever = IVec3(3, floorY, 14);
    const piston = IVec3(4, floorY, 14);
    w.setBlock(lever, id('lever_off'));
    w.setBlock(piston, id('piston_e'));
    w.setBlock(const IVec3(5, floorY, 14), id('cobblestone'));
    run(w, 0.2);
    w.circuits.useBlock(lever);
    run(w, 0.2);
    expect(at(w, 4, floorY, 14), 'piston_e_on');
    expect(at(w, 5, floorY, 14), 'air');
    expect(at(w, 6, floorY, 14), 'cobblestone');
    w.circuits.useBlock(lever);
    run(w, 0.2);
    expect(at(w, 4, floorY, 14), 'piston_e');
    expect(at(w, 6, floorY, 14), 'cobblestone');
    // Blocked: cobblestone in front with stone behind it.
    final w2 = flatWorld();
    w2.setBlock(lever, id('lever_off'));
    w2.setBlock(piston, id('piston_e'));
    w2.setBlock(const IVec3(5, floorY, 14), id('cobblestone'));
    w2.setBlock(const IVec3(6, floorY, 14), id('stone'));
    run(w2, 0.2);
    w2.circuits.useBlock(lever);
    run(w2, 0.2);
    expect(at(w2, 4, floorY, 14), 'piston_e');
    expect(at(w2, 5, floorY, 14), 'cobblestone');
  });

  test('WIRE meshes as a 1/8 slab; strong emitters land on the glow surface', () {
    ChunkMeshResult mesh(void Function(Uint8List c) place) {
      final c = Uint8List(16 * 16 * 128);
      place(c);
      final mesher = ChunkMesher(
          palette: Blocks.palette(), shape: Blocks.shapes(), opaque: Blocks.opaqueTable(), emission: Blocks.emission());
      return mesher.build(0, 0, [c, ...ChunkMesher.noNeighbours]);
    }

    int cell(int x, int y, int z) => x + 16 * (z + 16 * y);
    void floor(Uint8List c) {
      for (var i = 0; i < 16 * 16 * 40; i++) {
        c[i] = 1;
      }
    }

    // Floating in air: six faces, nothing culled.
    expect(mesh((c) => c[cell(8, 40, 8)] = id('wire_off')).solid.faceCount, 6);
    // On stone: the bottom face meets an opaque block and is culled.
    final bare = mesh(floor).solid.faceCount;
    expect(mesh((c) {
      floor(c);
      c[cell(8, 40, 8)] = id('wire_on');
    }).solid.faceCount, bare + 5);
    final lamp = mesh((c) => c[cell(8, 40, 8)] = id('redstone_lamp_on'));
    expect([lamp.glow.faceCount, lamp.solid.faceCount, lamp.faces], [6, 0, 6]);
    final dark = mesh((c) => c[cell(8, 40, 8)] = id('redstone_lamp_off'));
    expect([dark.glow.faceCount, dark.solid.faceCount], [0, 6]);
  });

  test('redstone ore veins only below y 30', () {
    final gen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 42);
    final ore = id('redstone_ore');
    var deep = 0, shallow = 0;
    for (var cz = 0; cz < 3; cz++) {
      for (var cx = 0; cx < 3; cx++) {
        final blocks = gen.generate(cx, cz);
        for (var i = 0; i < blocks.length; i++) {
          if (blocks[i] != ore) continue;
          if (i ~/ 256 < 30) {
            deep += 1;
          } else {
            shallow += 1;
          }
        }
      }
    }
    expect(deep, greaterThan(0));
    expect(shallow, 0);
  });
}
