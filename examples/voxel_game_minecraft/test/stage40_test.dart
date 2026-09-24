import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/game/game_state.dart';
import 'package:voxel_game_minecraft/src/player/player.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

/// Stage 40: reach — what is nearest is what is acted on — the step every
/// creature jumps instead of being lifted up, the swim, and the playground's
/// endless stats. What a creature does with all this is measured by
/// `--move-probe` and `--reach-probe`, which need the scene.
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

  /// A body 0.3 wide standing at ([x], [z]) on the floor.
  VoxelBody bodyAt(VoxelWorld w, double x, double z) => VoxelBody()
    ..setup(w, 0.3, 1.75)
    ..position = Vector3(x, floorY + 0.01, z);

  test('a creature is out of reach behind a block, and in reach once it is broken', () {
    final w = flatWorld();
    final eye = Vector3(4.5, floorY + 1.6, 8.5);
    final dir = Vector3(1, 0, 0);
    final mob = bodyAt(w, 7.5, 8.5);
    // Nothing in the way: the creature is the nearest thing on the line.
    expect(Reach.toBarrier(w, eye, dir, 5.0), double.infinity);
    expect(Reach.nearestBody([mob], eye, dir, maxDist: 5.0), same(mob));

    // A stone block between the two: the wall is nearer, so the swing stops.
    w.setBlock(const IVec3(6, floorY + 1, 8), Blocks.indexOf('stone'));
    final wall = Reach.toBarrier(w, eye, dir, 5.0);
    expect(wall, closeTo(1.5, 1e-6));
    expect(Reach.nearestBody([mob], eye, dir, maxDist: 5.0, blockedAt: wall), isNull);

    // Broken again, the same swing lands.
    w.setBlock(const IVec3(6, floorY + 1, 8), Blocks.air);
    expect(Reach.nearestBody([mob], eye, dir, maxDist: 5.0, blockedAt: Reach.toBarrier(w, eye, dir, 5.0)), same(mob));
  });

  test('grass is aimed at but never in the way; a wall is both', () {
    final w = flatWorld();
    final eye = Vector3(4.5, floorY + 0.5, 8.5);
    final dir = Vector3(1, 0, 0);
    w.setBlock(const IVec3(6, floorY, 8), Blocks.indexOf('tall_grass'));
    // The crosshair picks the grass (it is mined), the swing crosses it.
    expect(Reach.toBlock(w, eye, dir, 5.0), closeTo(1.5, 1e-6));
    expect(Reach.toBarrier(w, eye, dir, 5.0), double.infinity);
    // A fence is passed between its posts and stopped at one.
    w.setBlock(const IVec3(6, floorY, 8), Blocks.indexOf('oak_fence'));
    expect(Reach.toBarrier(w, eye, dir, 5.0), closeTo(1.875, 1e-6));
    final past = Vector3(4.5, floorY + 0.5, 8.9); // level with the gap beside the post
    expect(Reach.toBarrier(w, past, dir, 5.0), double.infinity);
  });

  test('a step is never lifted onto: a slab reads half a step, a block a full one, a wall none', () {
    final w = flatWorld();
    w.setBlock(const IVec3(6, floorY, 8), Blocks.indexOf('oak_slab'));
    final body = bodyAt(w, 4.5, 8.5);
    void walkInto() {
      for (var i = 0; i < 60 && !body.hitWall; i++) {
        body.applyGravity(dt);
        body.velocity.x = 3.0;
        body.move(dt);
      }
    }

    walkInto();
    expect(body.hitWall, isTrue);
    expect(body.stepAhead(), VoxelBody.halfStep);
    final atSlab = body.position.y;

    final full = flatWorld();
    full.setBlock(const IVec3(6, floorY, 8), Blocks.indexOf('oak_planks'));
    final walker = bodyAt(full, 4.5, 8.5);
    for (var i = 0; i < 60 && !walker.hitWall; i++) {
      walker.applyGravity(dt);
      walker.velocity.x = 3.0;
      walker.move(dt);
    }
    expect(walker.stepAhead(), VoxelBody.fullStep);
    // The step is read, never taken: asking does not move the body.
    expect(walker.position.y, closeTo(floorY + VoxelBody.skin, 1e-3));
    expect(atSlab, closeTo(floorY + VoxelBody.skin, 1e-3));

    // Two blocks stacked are a wall, and a wall is no step at all.
    full.setBlock(const IVec3(6, floorY + 1, 8), Blocks.indexOf('oak_planks'));
    expect(walker.stepAhead(), 0.0);
  });

  test('a body deep in water swims instead of standing on the floor of it', () {
    final w = flatWorld();
    final water = Blocks.indexOf('water');
    for (var y = floorY; y < floorY + 4; y++) {
      for (var x = 4; x <= 6; x++) {
        for (var z = 7; z <= 9; z++) {
          w.setBlock(IVec3(x, y, z), water);
        }
      }
    }
    final body = VoxelBody()
      ..setup(w, 0.3, 1.75)
      ..position = Vector3(5.5, floorY + 2.0, 8.5);
    body.move(dt);
    expect(body.inLiquid, isTrue);
    expect(body.wading, isFalse, reason: 'four blocks of water are swum, not waded');
    // Sinking is the liquid's slow fall, never the air's.
    final before = body.velocity.y;
    body.applyGravity(dt);
    expect(before - body.velocity.y, closeTo(body.liquidGravity * dt, 1e-6));
    // One block of water over the floor is waded through on foot.
    final puddle = flatWorld();
    puddle.setBlock(const IVec3(5, floorY, 8), water);
    final wader = VoxelBody()
      ..setup(puddle, 0.3, 1.75)
      ..position = Vector3(5.5, floorY + 0.5, 8.5);
    for (var i = 0; i < 90; i++) {
      wader.applyGravity(dt);
      wader.move(dt);
    }
    expect(wader.onFloor, isTrue);
    expect(wader.wading, isTrue);
  });

  test('the playground spends no stamina and no mana; every other world does', () {
    final gs = GameState.instance;
    final was = gs.playground;
    gs.playground = false;
    expect(Player.canSpend(40.0, 50.0), isFalse);
    expect(Player.canSpend(40.0, 40.0), isTrue);
    expect(Player.afterSpending(40.0, 15.0), 25.0);
    expect(Player.afterSpending(40.0, 100.0), 0.0, reason: 'a spend never goes under zero');

    gs.playground = true;
    expect(Player.canSpend(0.0, 1000.0), isTrue, reason: 'a showroom never runs out');
    expect(Player.afterSpending(100.0, 25.0), 100.0);
    gs.playground = was;
  });
}
