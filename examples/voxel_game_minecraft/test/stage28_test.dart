import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/core/items.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/core/recipes.dart';
import 'package:voxel_game_minecraft/src/entities/minecart.dart';
import 'package:voxel_game_minecraft/src/game/rails.dart';
import 'package:voxel_game_minecraft/src/world/terrain_generator.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 28's headless proofs (Godot `--stage28` covers the rest in the app):
/// the appended rail blocks, orientation from neighbours (straights, corners,
/// slopes), the graph walk, the cart's physics on flats, slopes, corners and
/// powered rails, the powered run on the circuit, the save row, and the rail
/// down every mine corridor.
void main() {
  const floorY = 10; // stone fills y 0..9, rails sit on y 10
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

  String at(VoxelWorld w, int x, int y, int z) => Blocks.idOf(w.getBlockXYZ(x, y, z));

  Minecart cartOn(VoxelWorld w, IVec3 cell, [String kind = 'minecart']) =>
      Minecart()..setupCart(w, cell, kind, model: false);

  /// Steps the cart and the circuit together at 60 Hz, as `Game._tick` does.
  void run(VoxelWorld w, Minecart c, double seconds, [bool Function()? stop]) {
    for (var i = 0; i < (seconds / dt).round(); i++) {
      c.update(dt);
      w.circuits.tick(dt);
      if (stop != null && stop()) return;
    }
  }

  test('14 rail blocks appended after the pistons, in Godot order; items and recipes', () {
    const order = [
      'rail_ns', 'rail_ew', 'rail_ne', 'rail_nw', 'rail_se', 'rail_sw',
      'rail_slope_n', 'rail_slope_e', 'rail_slope_s', 'rail_slope_w',
      'powered_rail_ns', 'powered_rail_ew', 'powered_rail_ns_on', 'powered_rail_ew_on',
    ];
    final last = id('piston_w_on');
    for (var i = 0; i < order.length; i++) {
      expect(id(order[i]), last + 1 + i, reason: order[i]);
      expect(Blocks.isRail(id(order[i])), isTrue);
      expect(Blocks.isSolid(id(order[i])), isFalse);
    }
    expect(Blocks.idOf(last + 1 + order.length), 'obsidian'); // stage 29 appends after the rails
    expect(Blocks.isRailSlope(id('rail_slope_e')), isTrue);
    expect(Blocks.isRailSlope(id('rail_ne')), isFalse);
    expect(Blocks.isPoweredRail(id('powered_rail_ew_on')), isTrue);
    expect(Blocks.isPoweredRail(id('rail_ew')), isFalse);
    expect(Blocks.lightOf(id('powered_rail_ns_on')), 4);
    expect(Blocks.dropOf(id('rail_slope_w')), 'rail');
    expect(Blocks.dropOf(id('powered_rail_ew_on')), 'powered_rail');
    expect(Blocks.shapeOf(id('powered_rail_ew')), BlockShape.railEw);
    expect(Blocks.generatorIds()['rail_ew'], id('rail_ew'));
    expect(Items.blockOf('rail'), id('rail_ns'));
    expect(Items.blockOf('powered_rail'), id('powered_rail_ns'));
    for (final item in ['minecart', 'chest_minecart']) {
      expect(Items.has(item), isTrue);
      expect(Items.kind(item), ItemKind.equipment);
    }
    for (final state in ['rail_ew', 'rail_slope_n', 'powered_rail_ns_on']) {
      expect(Items.has(state), isFalse, reason: state);
    }
    final rail = Recipes.list.firstWhere((r) => r.result == 'rail');
    expect(rail.count, 16);
    expect(Recipes.list.firstWhere((r) => r.result == 'powered_rail').count, 6);
    expect(Recipes.list.any((r) => r.result == 'minecart'), isTrue);
    expect(Recipes.list.any((r) => r.result == 'chest_minecart'), isTrue);
  });

  test('connections: straights, curves and slopes; a powered rail keeps its straights and state', () {
    expect(Rails.connections(id('rail_ns')), const [IVec3(0, 0, -1), IVec3(0, 0, 1)]);
    expect(Rails.connections(id('rail_sw')), const [IVec3(0, 0, 1), IVec3(-1, 0, 0)]);
    expect(Rails.connections(id('rail_slope_e')), const [IVec3(-1, 0, 0), IVec3(1, 1, 0)]);
    expect(Rails.connections(id('powered_rail_ew_on')), const [IVec3(1, 0, 0), IVec3(-1, 0, 0)]);
    expect(Rails.suffixOf(id('powered_rail_ns_on')), 'ns');
    expect(Rails.withSuffix(id('rail_ns'), 'slope_w'), id('rail_slope_w'));
    expect(Rails.withSuffix(id('powered_rail_ns_on'), 'ew'), id('powered_rail_ew_on'));
    expect(Rails.withSuffix(id('powered_rail_ns'), 'slope_n'), id('powered_rail_ns'));
    expect(Rails.withSuffix(id('powered_rail_ns'), 'ne'), id('powered_rail_ew')); // "ne" ends in e, as Godot
  });

  test('orient: a line, a corner, a slope toward a rail one up, and a break re-turns the neighbours', () {
    final w = flatWorld();
    final rail = id('rail_ns');
    // Three in a row along x.
    for (var x = 2; x <= 4; x++) {
      Rails.place(w, IVec3(x, floorY, 2), rail);
    }
    expect([for (var x = 2; x <= 4; x++) at(w, x, floorY, 2)], ['rail_ew', 'rail_ew', 'rail_ew']);
    // Turn south at the east end: the corner joins west and south.
    Rails.place(w, const IVec3(4, floorY, 3), rail);
    Rails.place(w, const IVec3(4, floorY, 4), rail);
    expect(at(w, 4, floorY, 2), 'rail_sw');
    expect(at(w, 4, floorY, 3), 'rail_ns');
    // A slope: a solid step with a rail on it past the west end.
    w.setBlock(const IVec3(1, floorY, 2), id('stone'));
    Rails.place(w, const IVec3(1, floorY + 1, 2), rail);
    expect(at(w, 2, floorY, 2), 'rail_slope_w');
    // A powered rail never slopes.
    w.setBlock(const IVec3(9, floorY, 9), id('stone'));
    Rails.place(w, const IVec3(9, floorY + 1, 9), rail);
    expect(at(w, 10, floorY, 9), 'air');
    Rails.place(w, const IVec3(10, floorY, 9), id('powered_rail_ns'));
    expect(at(w, 10, floorY, 9), 'powered_rail_ns'); // the rail one up would slope a plain rail; no flat side, so the default axis
    Rails.place(w, const IVec3(10, floorY, 9), id('rail_ns'));
    w.setBlock(const IVec3(10, floorY, 9), Blocks.air);
    Rails.place(w, const IVec3(10, floorY, 9), id('rail_ns'));
    expect(at(w, 10, floorY, 9), 'rail_slope_w'); // the same spot with a plain rail climbs
    // Breaking the corner's south neighbour straightens the corner back.
    w.setBlock(const IVec3(4, floorY, 3), Blocks.air);
    w.setBlock(const IVec3(4, floorY, 4), Blocks.air);
    Rails.removed(w, const IVec3(4, floorY, 3));
    expect(at(w, 4, floorY, 2), 'rail_ew');
  });

  test('the graph: nextCell steps along ends and down onto a slope, endToward finds the way back', () {
    final w = flatWorld();
    w.setBlock(const IVec3(3, floorY, 2), id('rail_ew'));
    w.setBlock(const IVec3(4, floorY, 2), id('rail_slope_e'));
    w.setBlock(const IVec3(4, floorY, 3), id('stone'));
    w.setBlock(const IVec3(5, floorY, 2), id('stone'));
    w.setBlock(const IVec3(5, floorY + 1, 2), id('rail_ew'));
    const e = IVec3(1, 0, 0);
    expect(Rails.nextCell(w, const IVec3(3, floorY, 2), e), const IVec3(4, floorY, 2));
    expect(Rails.nextCell(w, const IVec3(4, floorY, 2), const IVec3(1, 1, 0)), const IVec3(5, floorY + 1, 2));
    // From the top going west, the flat end reaches the slope one cell down.
    expect(Rails.nextCell(w, const IVec3(5, floorY + 1, 2), const IVec3(-1, 0, 0)), const IVec3(4, floorY, 2));
    expect(Rails.endToward(w, const IVec3(4, floorY, 2), const IVec3(5, floorY + 1, 2)), const IVec3(1, 1, 0));
    expect(Rails.endToward(w, const IVec3(4, floorY, 2), const IVec3(4, floorY, 3)), IVec3.zero);
    // A line that ends answers the cell itself.
    expect(Rails.nextCell(w, const IVec3(3, floorY, 2), const IVec3(-1, 0, 0)), const IVec3(3, floorY, 2));
  });

  test('a cart coasts to the end of the line and stops; up a slope it slows, down it speeds up', () {
    final w = flatWorld();
    final rail = id('rail_ns');
    for (var x = 0; x <= 12; x++) {
      Rails.place(w, IVec3(x, floorY, 5), rail);
    }
    // x 13 one up, a plateau at two up: the probe's slope.
    w.setBlock(const IVec3(13, floorY, 5), id('stone'));
    Rails.place(w, const IVec3(13, floorY + 1, 5), rail);
    w.setBlock(const IVec3(14, floorY + 1, 5), id('stone'));
    w.setBlock(const IVec3(15, floorY + 1, 5), id('stone'));
    Rails.place(w, const IVec3(14, floorY + 2, 5), rail);
    Rails.place(w, const IVec3(15, floorY + 2, 5), rail);
    expect(at(w, 12, floorY, 5), 'rail_slope_e');
    expect(at(w, 13, floorY + 1, 5), 'rail_slope_e');
    final c = cartOn(w, const IVec3(11, floorY, 5));
    c.head(Rails.w);
    expect(c.heading(), Rails.w);
    c.speed = 6.0;
    run(w, c, 3.0);
    expect(c.stopped, isTrue);
    expect(c.speed, 0.0);
    expect(c.cell, const IVec3(0, floorY, 5));
    expect(c.position.x, closeTo(0.0, 1e-6));
    // Uphill from x 8 at 6 m/s: the numbers Godot logged (3.93 at the top).
    c.placeOn(const IVec3(8, floorY, 5));
    c.head(Rails.e);
    c.speed = 6.0;
    run(w, c, 5.0, () => c.cell.x >= 14);
    expect(c.cell.x, 14);
    expect(c.speed, inInclusiveRange(3.7, 4.1));
    // From rest on the upper slope cell heading down: gravity takes it.
    c.placeOn(const IVec3(13, floorY + 1, 5));
    c.head(Rails.w);
    run(w, c, 1.5);
    expect(c.speed, greaterThan(1.0));
    expect(c.position.x, lessThan(13.0));
  });

  test('a cart through a corner leaves on the other axis', () {
    final w = flatWorld();
    final rail = id('rail_ns');
    for (var x = 2; x <= 6; x++) {
      Rails.place(w, IVec3(x, floorY, 2), rail);
    }
    for (var z = 3; z <= 8; z++) {
      Rails.place(w, IVec3(6, floorY, z), rail);
    }
    expect(at(w, 6, floorY, 2), 'rail_sw');
    final c = cartOn(w, const IVec3(3, floorY, 2));
    c.head(Rails.e);
    c.speed = 4.0;
    run(w, c, 3.0, () => c.cell.z >= 3);
    expect(c.cell, const IVec3(6, floorY, 3));
    expect(c.heading(), Rails.s);
  });

  test('powered rails: a lever lights the run within 8, a dead one brakes, a live one launches', () {
    final w = flatWorld();
    // Ten powered rails along x, a lever beside the first.
    for (var x = 1; x <= 10; x++) {
      Rails.place(w, IVec3(x, floorY, 4), id('powered_rail_ns'));
    }
    expect(at(w, 5, floorY, 4), 'powered_rail_ew');
    final lever = const IVec3(1, floorY, 5);
    w.setBlock(lever, id('lever_off'));
    final c = cartOn(w, const IVec3(4, floorY, 4));
    c.head(Rails.e);
    c.speed = 4.0;
    run(w, c, 1.0);
    expect(c.stopped, isTrue, reason: 'the unpowered rail brakes the cart to rest');
    expect(c.speed, 0.0);
    w.circuits.useBlock(lever);
    var peak = 0.0;
    run(w, c, 2.0, () {
      peak = peak > c.speed ? peak : c.speed;
      return false;
    });
    expect(at(w, 1, floorY, 4), 'powered_rail_ew_on');
    expect(at(w, 9, floorY, 4), 'powered_rail_ew_on'); // 8 steps from the lit cell
    expect(at(w, 10, floorY, 4), 'powered_rail_ew'); // 9 steps: dark
    expect(peak, greaterThan(4.0));
    // The lever off: every cell goes dark again.
    w.circuits.useBlock(lever);
    run(w, c, 0.5);
    expect(at(w, 1, floorY, 4), 'powered_rail_ew');
  });

  test('a cart row survives JSON: cell, ends, t, speed and a chest cart\'s cargo', () {
    final w = flatWorld();
    for (var x = 2; x <= 8; x++) {
      Rails.place(w, IVec3(x, floorY, 2), id('rail_ns'));
    }
    final c = cartOn(w, const IVec3(3, floorY, 2), 'chest_minecart');
    c.cargo!.add('apple', 3);
    c.head(Rails.e);
    c.speed = 2.0;
    run(w, c, 0.4);
    final data = c.toJson();
    expect(data.keys.toSet(), {'kind', 'cell', 't', 'speed', 'from', 'to', 'cargo'});
    final back = cartOn(w, const IVec3(2, floorY, 2), 'chest_minecart');
    back.fromJson(Map<String, dynamic>.from(data));
    expect(back.cell, c.cell);
    expect(back.t, closeTo(c.t, 1e-9));
    expect(back.speed, closeTo(c.speed, 1e-9));
    expect(back.heading(), Rails.e);
    expect((back.position - c.position).length, lessThan(1e-9));
    expect(back.cargo!.countOf('apple'), 3);
    expect(cartOn(w, const IVec3(4, floorY, 2)).toJson().containsKey('cargo'), isFalse);
  });

  test('a cart ray hit and the seat', () {
    final w = flatWorld();
    Rails.place(w, const IVec3(5, floorY, 5), id('rail_ns'));
    final c = cartOn(w, const IVec3(5, floorY, 5));
    final origin = Vector3(5.5, floorY + 1.5, 8.5);
    expect(c.rayHits(origin, Vector3(0, -0.3, -1)..normalize(), 4.0), isTrue);
    expect(c.rayHits(origin, Vector3(0, 1, 0), 4.0), isFalse);
    expect(c.rayHits(origin, Vector3(0, -0.3, -1)..normalize(), 1.0), isFalse); // out of reach
    expect(c.seat().y, closeTo(floorY + Minecart.railTop + 0.3, 1e-5)); // Vector3 is float32
  });

  test('every abandoned mine lays rail_ew down its corridor, from the shaft to the chest', () {
    final gen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 42);
    final mines = <({int x, int y, int z, int type})>{};
    for (var dz = -40; dz <= 40; dz += 4) {
      for (var dx = -40; dx <= 40; dx += 4) {
        for (final s in gen.structuresNear(dx, dz)) {
          if (s.type == TerrainGenerator.structMine) mines.add(s);
        }
      }
    }
    expect(mines, isNotEmpty);
    // The seed 42 mine Godot's probe reached (and the nearest one checked).
    final m = mines.firstWhere((s) => s.x == -111 && s.z == -344, orElse: () => mines.first);
    final fy = TerrainGenerator.mineFloorY + 1;
    final cache = <(int, int), Uint8List>{};
    int blockAt(int x, int y, int z) {
      final cx = (x / 16).floor(), cz = (z / 16).floor();
      final b = cache.putIfAbsent((cx, cz), () => gen.generate(cx, cz));
      return b[TerrainGenerator.index(x - cx * 16, y, z - cz * 16)];
    }

    var rails = 0, chestAt = -1;
    for (var x = 1; x <= 31; x++) {
      final b = blockAt(m.x + x, fy, m.z);
      if (b == id('rail_ew')) rails++;
      if (b == id('chest') && chestAt < 0) chestAt = x;
    }
    expect(chestAt, inInclusiveRange(20, 30));
    // Every corridor cell before the chest is rail, except a spawner a third of the time.
    expect(rails, inInclusiveRange(chestAt - 2, chestAt - 1));
    // ignore: avoid_print
    print('mine at (${m.x}, ${m.y}, ${m.z}): rails=$rails chest at +$chestAt');
  });
}
