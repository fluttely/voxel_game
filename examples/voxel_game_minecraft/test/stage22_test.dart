import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/core/items.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 22's headless proofs (Godot `--stage22`): per-shape collision boxes and
/// the cellular liquid flow, on one hand-filled chunk.
void main() {
  const floorY = 10; // stone fills y 0..9, the walk floor is y 10
  const dt = 1.0 / 60.0;

  VoxelWorld flatWorld() {
    final w = VoxelWorld(seedValue: 42, loadRadius: 1);
    final c = Uint8List(VoxelWorld.volume);
    for (var i = 0; i < 16 * 16 * floorY; i++) {
      c[i] = Blocks.indexOf('stone');
    }
    w.chunks[(x: 0, z: 0)] = c;
    return w;
  }

  /// Walks a 0.3 / 1.75 body along +x at 4.3 m/s for [ticks], jumping every step
  /// it meets (nothing is ever lifted into place), plus one jump at a wall past
  /// [jumpAfterX] when [jump]. [barrier] meets fences as a penned mob does.
  ({double x, double y, double maxX, double maxY}) walk(VoxelWorld w, double startX, double stopX, int ticks,
      {bool jump = false, double jumpAfterX = 0.0, bool barrier = false}) {
    final body = VoxelBody()
      ..setup(w, 0.3, 1.75)
      ..fenceBarrier = barrier;
    body.position = Vector3(startX, floorY + 0.1, 8.5);
    var maxX = body.position.x, maxY = body.position.y;
    var jumped = false;
    for (var i = 0; i < ticks; i++) {
      body.applyGravity(dt);
      body.velocity.x = body.position.x < stopX ? 4.3 : 0.0;
      body.move(dt);
      if (body.position.x < stopX && body.stepAhead() > 0.0) body.velocity.y = 8.6;
      if (jump && !jumped && body.hitWall && body.onFloor && body.position.x > jumpAfterX) {
        jumped = true;
        body.velocity.y = 8.6;
      }
      if (body.position.x > maxX) maxX = body.position.x;
      if (body.position.y > maxY) maxY = body.position.y;
    }
    return (x: body.position.x, y: body.position.y, maxX: maxX, maxY: maxY);
  }

  test('collision boxes follow the shape; flowing liquids are appended and not items', () {
    expect(Blocks.collisionBoxes(Blocks.indexOf('stone')).single.y1, 1.0);
    expect(Blocks.collisionBoxes(Blocks.indexOf('water')), isEmpty);
    expect(Blocks.collisionBoxes(Blocks.indexOf('oak_slab')).single.y1, 0.5);
    final post = Blocks.collisionBoxes(Blocks.indexOf('oak_fence')).single;
    expect([post.x0, post.y1, post.x1], [0.375, 1.0, 0.625]);
    final north = Blocks.collisionBoxes(Blocks.indexOf('oak_stairs_n'));
    expect(north.length, 2);
    expect([north[1].y0, north[1].z0, north[1].z1], [0.5, 0.0, 0.5]);
    final east = Blocks.collisionBoxes(Blocks.indexOf('stone_stairs_e'));
    expect([east[1].x0, east[1].x1], [0.5, 1.0]);
    // Index order is the save contract: the flowing forms follow the stairs.
    expect(Blocks.indexOf('water_flow'), Blocks.indexOf('stone_stairs_w') + 1);
    expect(Blocks.indexOf('lava_flow'), Blocks.indexOf('stone_stairs_w') + 2);
    expect(Blocks.liquidKind(Blocks.indexOf('water_flow')), 'water');
    expect(Blocks.liquidKind(Blocks.indexOf('lava')), 'lava');
    expect(Blocks.liquidKind(Blocks.indexOf('stone')), '');
    expect(Blocks.isLiquidSource(Blocks.indexOf('water')), isTrue);
    expect(Blocks.isLiquidSource(Blocks.indexOf('water_flow')), isFalse);
    expect(Items.has('water_flow'), isFalse);
  });

  test('a body jumps onto a slab, climbs stairs on its own and crosses a fence a mob cannot', () {
    final w = flatWorld();
    w.setBlock(const IVec3(5, floorY, 8), Blocks.indexOf('oak_slab'));
    final slab = walk(w, 3.5, 5.2, 90);
    expect(slab.y, closeTo(floorY + 0.5, 0.01));

    final w2 = flatWorld();
    w2.setBlock(const IVec3(5, floorY, 8), Blocks.stairsFacing(Blocks.indexOf('oak_stairs_n'), 1, 0));
    w2.setBlock(const IVec3(6, floorY, 8), Blocks.indexOf('oak_planks'));
    final stairs = walk(w2, 3.5, 6.3, 150);
    expect(stairs.y, closeTo(floorY + 1.0, 0.01));

    final w3 = flatWorld();
    w3.setBlock(const IVec3(9, floorY, 8), Blocks.indexOf('oak_fence'));
    // The player meets the fence as drawn, one block, and jumps over it.
    final crossed = walk(w3, 3.5, 20.0, 220);
    expect(crossed.maxX, greaterThan(10.0));
    final fence = walk(w3, 3.5, 20.0, 220, jump: true, jumpAfterX: 8.5, barrier: true);
    // A mob stops flush with the post's face, not the cell's.
    expect(fence.x, closeTo(9.375 - 0.3 - VoxelBody.skin, 0.001));
    // A 8.6 m/s jump rises ~1.4 m and never clears the 1.5 m barrier.
    expect(fence.maxY, lessThan(floorY + fenceBarrierHeight));
    expect(fence.maxX, lessThan(9.7));

    // A half step never beats a full-height wall: two planks stacked stop the body.
    final w4 = flatWorld();
    w4.setBlock(const IVec3(6, floorY, 8), Blocks.indexOf('oak_planks'));
    w4.setBlock(const IVec3(6, floorY + 1, 8), Blocks.indexOf('oak_planks'));
    final wall = walk(w4, 3.5, 20.0, 120);
    expect(wall.y, closeTo(floorY, 0.01));
    expect(wall.x, closeTo(6.0 - 0.3 - VoxelBody.skin, 0.001));
  });

  test('water spreads four steps, drains when the source goes, lava meets water as cobblestone', () {
    final w = flatWorld();
    void settle(double seconds) {
      for (var t = 0.0; t < seconds; t += dt) {
        w.tickFlow(dt);
      }
    }

    ({int water, int lava, int hard, int dist}) count() {
      var water = 0, lava = 0, hard = 0, dist = 0;
      for (var x = 0; x < 16; x++) {
        for (var z = 0; z < 16; z++) {
          for (var y = floorY; y < floorY + 4; y++) {
            final b = IVec3(x, y, z);
            final id = w.getBlock(b);
            final kind = Blocks.liquidKind(id);
            if (kind == 'water') water++;
            if (kind == 'lava') lava++;
            if (kind != '' && w.flowDistOf(b) > dist) dist = w.flowDistOf(b);
            if (id == Blocks.indexOf('cobblestone')) hard++;
          }
        }
      }
      return (water: water, lava: lava, hard: hard, dist: dist);
    }

    const source = IVec3(8, floorY + 2, 8);
    w.setBlock(source, Blocks.indexOf('water'));
    settle(3.0);
    final spread = count();
    // The source, the flowing cell under it, and a diamond of radius 4 on the
    // floor (1 + 4 + 8 + 12 + 16): 43, Godot's figure.
    expect(spread.water, 43);
    expect(spread.dist, 4);
    expect(w.flowPending, 0);

    w.setBlock(source, Blocks.air);
    settle(3.0);
    expect(count().water, 0);

    w.setBlock(const IVec3(4, floorY + 1, 4), Blocks.indexOf('lava'));
    w.setBlock(const IVec3(4, floorY + 1, 6), Blocks.indexOf('water'));
    settle(3.0);
    final mixed = count();
    expect(mixed.hard, greaterThanOrEqualTo(1));
  });

  test('a client world never flows', () {
    final w = flatWorld()..flowEnabled = false;
    w.setBlock(const IVec3(8, floorY + 2, 8), Blocks.indexOf('water'));
    for (var i = 0; i < 120; i++) {
      w.tickFlow(dt);
    }
    expect(w.flowUpdates, 0);
    expect(w.flowPending, 0);
  });
}
