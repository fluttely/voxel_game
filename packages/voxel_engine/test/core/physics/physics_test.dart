import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

const int _stone = 1;
const int _water = 2;
const int _slab = 3;
const int _glass = 4;
const int _fence = 5;
const int _ladder = 6;

final _table = VoxelBlockTable(const [
  VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.5),
  VoxelBlockDef(
      shape: BlockShape.liquid, solid: false, opaque: false, r: 0.2, g: 0.4, b: 0.8, a: 0.6, liquidKind: 0, liquidSource: true),
  VoxelBlockDef(shape: BlockShape.slab, solid: true, opaque: false, r: 0.7, g: 0.5, b: 0.3),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: false, r: 0.9, g: 0.9, b: 1.0, a: 0.3),
  VoxelBlockDef(shape: BlockShape.fence, solid: true, opaque: false, r: 0.4, g: 0.3, b: 0.2),
  VoxelBlockDef(shape: BlockShape.ladder, solid: false, opaque: false, r: 0.6, g: 0.45, b: 0.25),
]);

/// A sparse world: stone floor filling y 0..9 everywhere, plus placed cells.
class _World implements VoxelQuery {
  final Map<IVec3, int> cells = {};

  @override
  VoxelBlockTable get table => _table;

  @override
  int getBlockXYZ(int x, int y, int z) => cells[IVec3(x, y, z)] ?? (y >= 0 && y < 10 ? _stone : 0);
}

void main() {
  late _World world;
  late VoxelBody body;

  setUp(() {
    world = _World();
    body = VoxelBody()..setup(world, 0.3, 1.8);
  });

  void run(double seconds, void Function() eachTick) {
    for (var t = 0.0; t < seconds; t += 1 / 60) {
      eachTick();
      body.applyGravity(1 / 60);
      body.move(1 / 60);
    }
  }

  test('a falling body lands flush on the floor', () {
    body.position = Vector3(4.5, 14.0, 4.5);
    run(1.5, () {});
    expect(body.onFloor, isTrue);
    expect(body.position.y, closeTo(10.0 + VoxelBody.skin, 1e-6));
  });

  test('walking into a wall stops at the face, minus the half width and skin', () {
    world.cells[const IVec3(7, 10, 4)] = _stone;
    world.cells[const IVec3(7, 11, 4)] = _stone;
    body.position = Vector3(4.5, 10.001, 4.5);
    run(1.0, () => body.velocity.x = 4.0);
    expect(body.hitWall, isTrue);
    expect(body.position.x, closeTo(7.0 - 0.3 - VoxelBody.skin, 1e-6));
  });

  test('a slab reads as a half step and is jumped, never lifted; a full-height wall is no step', () {
    world.cells[const IVec3(6, 10, 4)] = _slab;
    body.position = Vector3(4.5, 10.001, 4.5);
    var step = 0.0;
    var maxRise = 0.0;
    run(1.0, () {
      final before = body.position.y;
      body.velocity.x = 3.0;
      final ahead = body.stepAhead();
      if (ahead > 0.0) {
        step = ahead;
        body.velocity.y = 8.6;
      }
      final rise = body.position.y - before;
      if (rise > maxRise) maxRise = rise;
    });
    expect(step, VoxelBody.halfStep);
    expect(maxRise, lessThan(0.3), reason: 'a jump rises over several ticks; a lift arrives in one');
    expect(body.position.y, greaterThan(10.4));

    world.cells[const IVec3(9, 11, 4)] = _stone;
    world.cells[const IVec3(9, 12, 4)] = _stone;
    world.cells[const IVec3(9, 13, 4)] = _stone;
    final wall = VoxelBody()
      ..setup(world, 0.3, 1.8)
      ..position = Vector3(8.5, 10.001, 4.5);
    for (var tick = 0; tick < 20 && !wall.hitWall; tick++) {
      wall.velocity.x = 3.0;
      wall.move(1 / 60);
    }
    expect(wall.hitWall, isTrue);
    // Without gravity the sweep never lands, so stand the body on the floor.
    wall.onFloor = true;
    expect(wall.stepAhead(), 0.0, reason: 'both steps overlap the wall');
    expect(wall.position.y, closeTo(10.001, 1e-6), reason: 'vector_math stores float32');
  });

  test('a climber pushing into a wall three blocks high ends standing on top of it', () {
    for (var y = 10; y <= 12; y++) {
      world.cells[IVec3(7, y, 4)] = _stone;
    }
    body.position = Vector3(5.5, 10.001, 4.5);
    final push = Vector3(1, 0, 0);
    // The player's climb: while the wall is ahead, rise at 3.2; otherwise fall.
    for (var tick = 0; tick < 240; tick++) {
      if (body.wallAhead(push)) {
        body.velocity.y = 3.2;
      } else {
        body.applyGravity(1 / 60);
      }
      body.velocity.x = 3.0;
      body.move(1 / 60);
      if (body.position.x > 7.6) break;
    }
    expect(body.position.x, greaterThan(7.3), reason: 'past the wall face, on its top');
    body.velocity.x = 0;
    run(0.5, () {});
    expect(body.onFloor, isTrue);
    expect(body.position.y, closeTo(13.0 + VoxelBody.skin, 1e-3));
  });

  test('with the full step off, a one-block step is still jumped, never lifted in one tick', () {
    world.cells[const IVec3(7, 10, 4)] = _stone;
    world.cells[const IVec3(8, 10, 4)] = _stone;
    body.position = Vector3(5.5, 10.001, 4.5);
    var maxRise = 0.0;
    for (var tick = 0; tick < 120 && body.position.x < 7.6; tick++) {
      final before = body.position.y;
      body.applyGravity(1 / 60);
      body.velocity.x = 3.0;
      body.move(1 / 60);
      if (body.stepAhead(fullBlock: false) > 0.0 || (body.hitWall && body.onFloor && body.stepFits(1.02))) body.velocity.y = 8.6;
      maxRise = body.position.y - before > maxRise ? body.position.y - before : maxRise;
    }
    expect(body.position.x, greaterThan(7.3));
    expect(maxRise, lessThan(0.3), reason: 'a jump rises over several ticks');
    body.velocity.x = 0;
    run(0.5, () {});
    expect(body.position.y, closeTo(11.0 + VoxelBody.skin, 1e-3));

    world.cells[const IVec3(9, 11, 4)] = _stone;
    world.cells[const IVec3(9, 12, 4)] = _stone;
    final wall = VoxelBody()
      ..setup(world, 0.3, 1.8)
      ..position = Vector3(8.5, 11.001, 4.5);
    for (var tick = 0; tick < 20 && !wall.hitWall; tick++) {
      wall.velocity.x = 3.0;
      wall.move(1 / 60);
    }
    expect(wall.stepFits(1.02), isFalse, reason: 'a two-block wall is not jumped');
  });

  test('a fence line stops a body between its posts, not only at them', () {
    // Posts at z 3 and z 5 joined through z 4; the body walks +x at z 4.5,
    // where the lone posts would leave it a clear 0.75 m gap either side.
    for (var z = 3; z <= 5; z++) {
      world.cells[IVec3(7, 10, z)] = _fence;
    }
    body.position = Vector3(4.5, 10.001, 4.5);
    run(1.0, () => body.velocity.x = 4.0);
    expect(body.hitWall, isTrue);
    expect(body.position.x, closeTo(7.375 - 0.3 - VoxelBody.skin, 1e-6));
  });

  test('a lone fence is only its post: a body walks past beside it', () {
    world.cells[const IVec3(7, 10, 4)] = _fence;
    // The body spans z 3.7..4.3; the post starts at 4.375.
    body.position = Vector3(4.5, 10.001, 4.0);
    run(1.0, () => body.velocity.x = 4.0);
    expect(body.hitWall, isFalse);
    expect(body.position.x, greaterThan(8.0));
  });

  test('a fence arm reaches a wall it joins, as tall as the post', () {
    world.cells[const IVec3(7, 10, 4)] = _fence;
    world.cells[const IVec3(7, 10, 5)] = _stone;
    expect(fenceJoinsAt(world, 7, 10, 4), FenceJoin.south);
    final boxes = collisionBoxesAt(world, 7, 10, 4);
    expect(boxes, hasLength(1));
    final b = boxes.single;
    expect([b.x0, b.y0, b.z0, b.x1, b.y1, b.z1], [0.375, 0.0, 0.375, 0.625, 1.0, 1.0]);
    expect(collisionBoxesAt(world, 7, 10, 4, fenceBarrier: true).single.y1, fenceBarrierHeight);
  });

  test('a fence corner is two arms; a cross is two bars through the post', () {
    for (var joins = 0; joins < 16; joins++) {
      final boxes = fenceBoxesOf(joins);
      bool reaches(double x, double z) => boxes.any((b) => b.x0 <= x && x <= b.x1 && b.z0 <= z && z <= b.z1);
      expect(reaches(0.5, 0.5), isTrue, reason: 'the post, joins $joins');
      expect(reaches(0.0, 0.5), joins & FenceJoin.west != 0, reason: 'west, joins $joins');
      expect(reaches(1.0, 0.5), joins & FenceJoin.east != 0, reason: 'east, joins $joins');
      expect(reaches(0.5, 0.0), joins & FenceJoin.north != 0, reason: 'north, joins $joins');
      expect(reaches(0.5, 1.0), joins & FenceJoin.south != 0, reason: 'south, joins $joins');
      expect(reaches(0.0, 0.0) || reaches(1.0, 1.0), isFalse, reason: 'no corner is filled, joins $joins');
      expect(boxes.every((b) => b.y0 == 0.0 && b.y1 == 1.0), isTrue);
      final barrier = fenceBoxesOf(joins, barrier: true);
      expect(barrier, hasLength(boxes.length));
      for (var i = 0; i < boxes.length; i++) {
        final (a, b) = (boxes[i], barrier[i]);
        expect([b.x0, b.y0, b.z0, b.x1, b.y1, b.z1], [a.x0, a.y0, a.z0, a.x1, fenceBarrierHeight, a.z1]);
      }
    }
  });

  /// Walks [b] along +x at 4 m/s with a block-sandbox auto-step: a blocked
  /// body on the floor jumps 8.6 m/s (the player's jump) when a full step
  /// would fit, else the same jump anyway (a mob that tries its luck).
  double walkAndJump(VoxelBody b, double seconds) {
    var maxY = b.position.y;
    for (var t = 0.0; t < seconds; t += 1 / 60) {
      b.velocity.x = 4.0;
      b.applyGravity(1 / 60);
      b.move(1 / 60);
      if (b.hitWall && b.onFloor) b.velocity.y = 8.6;
      if (b.position.y > maxY) maxY = b.position.y;
    }
    return maxY;
  }

  test('a fence is one block to a player, who jumps onto it and over', () {
    for (var z = 3; z <= 5; z++) {
      world.cells[IVec3(7, 10, z)] = _fence;
    }
    body.position = Vector3(4.5, 10.001, 4.5);
    expect(body.stepFits(1.02), isTrue);
    walkAndJump(body, 3.0);
    expect(body.position.x, greaterThan(8.0));
  });

  test('a fence is a 1.5 m barrier to a penned body with the same jump', () {
    for (var z = 3; z <= 5; z++) {
      world.cells[IVec3(7, 10, z)] = _fence;
    }
    body
      ..fenceBarrier = true
      ..position = Vector3(4.5, 10.001, 4.5);
    final maxY = walkAndJump(body, 3.0);
    expect(body.position.x, closeTo(7.375 - 0.3 - VoxelBody.skin, 1e-6));
    expect(maxY, lessThan(10.0 + fenceBarrierHeight));
    expect(body.stepAhead(), 0.0, reason: 'no step fits over the barrier');
  });

  test('a ladder stops a body at its rungs, on the wall it hangs from', () {
    // A wall at x 8 (y 10..12), the ladder at x 7 hangs on it (+x).
    for (var y = 10; y <= 12; y++) {
      world.cells[IVec3(8, y, 4)] = _stone;
      world.cells[IVec3(7, y, 4)] = _ladder;
    }
    final box = collisionBoxesAt(world, 7, 10, 4).single;
    expect([box.x0, box.x1, box.z0, box.z1], [1 - ladderDepth, 1.0, ladderRail0, ladderRail1]);
    expect(selectionBoxAt(world, 7, 10, 4).x0, 7 + box.x0, reason: 'the outline is the collider');
    body.position = Vector3(5.5, 10.001, 4.5);
    run(1.5, () => body.velocity.x = 4.0);
    expect(body.hitWall, isTrue);
    expect(body.position.x, closeTo(8 - ladderDepth - 0.3 - VoxelBody.skin, 1e-6));
    // Still standing in the ladder's cell, so the climb reads it.
    expect(body.position.x.floor(), 7);
    // Climbing: velocity up along the rungs is never stopped by them.
    run(0.5, () {
      body.velocity.x = 4.0;
      body.velocity.y = 3.0 + 26.0 / 60;
    });
    expect(body.position.y, greaterThan(11.0));
  });

  test('a body a ladder is placed on walks out of it, never through the wall', () {
    world.cells[const IVec3(8, 10, 4)] = _stone;
    world.cells[const IVec3(8, 11, 4)] = _stone;
    body.position = Vector3(7.7 - VoxelBody.skin, 10.001, 4.5); // flush with the wall
    world.cells[const IVec3(7, 10, 4)] = _ladder;
    run(0.5, () => body.velocity.x = -2.0);
    expect(body.position.x, lessThan(7.0));
    body.position = Vector3(7.7 - VoxelBody.skin, 10.001, 4.5);
    run(0.2, () => body.velocity.x = 2.0);
    expect(body.position.x, lessThanOrEqualTo(7.7), reason: 'the wall still stops it');
    expect(body.position.y, closeTo(10.0 + VoxelBody.skin, 1e-3), reason: 'the ladder never lifts it');
  });

  test('a body sunk into the floor is still lifted out, not let through', () {
    body.position = Vector3(4.5, 9.8, 4.5);
    run(0.1, () {});
    expect(body.position.y, closeTo(10.0 + VoxelBody.skin, 1e-6));
    expect(body.onFloor, isTrue);
  });

  test('air and a non-fence answer from their shape', () {
    expect(collisionBoxesAt(world, 3, 20, 3), isEmpty);
    world.cells[const IVec3(3, 10, 3)] = _slab;
    expect(collisionBoxesAt(world, 3, 10, 3).single.y1, 0.5);
  });

  test('fluid sensing reports the liquid kind at feet and head', () {
    world.cells[const IVec3(4, 10, 4)] = _water;
    body.position = Vector3(4.5, 10.001, 4.5);
    body.move(0);
    expect(body.inLiquid, isTrue);
    expect(body.headInLiquid, isFalse);
    expect(body.feetLiquid, 0);
    expect(body.headLiquid, VoxelBlockDef.noLiquid);
  });

  test('leaving a liquid is decided at the soles, so a body at the surface does not flap', () {
    world.cells[const IVec3(4, 10, 4)] = _water;
    body.position = Vector3(4.5, 10.0, 4.5);
    body.move(0);
    expect(body.inLiquid, isTrue);
    // The feet probe rides 0.3 up, so here it has left the water cell while
    // the soles are still in it: the body stays wet.
    body.position = Vector3(4.5, 10.8, 4.5);
    body.move(0);
    expect(body.inLiquid, isTrue);
    // Clear of the cell altogether.
    body.position = Vector3(4.5, 11.05, 4.5);
    body.move(0);
    expect(body.inLiquid, isFalse);
  });

  test('a one-block puddle is waded, and neither the liquid nor the floor state flickers', () {
    world.cells[const IVec3(4, 10, 4)] = _water;
    body.position = Vector3(4.5, 10.2, 4.5);
    run(0.5, () {}); // settle on the floor under the water
    expect(body.wading, isTrue);
    expect(body.onFloor, isTrue);
    var liquidFlips = 0, floorFlips = 0;
    var wasWet = body.inLiquid, wasFloor = body.onFloor;
    run(2.0, () {
      if (body.inLiquid != wasWet) liquidFlips++;
      if (body.onFloor != wasFloor) floorFlips++;
      wasWet = body.inLiquid;
      wasFloor = body.onFloor;
    });
    expect(liquidFlips, 0);
    expect(floorFlips, 0);
    expect(body.wading, isTrue);
  });

  test('a body with its head under is swimming, not wading', () {
    for (var y = 10; y <= 12; y++) {
      world.cells[IVec3(4, y, 4)] = _water;
    }
    body.position = Vector3(4.5, 10.2, 4.5);
    run(0.5, () {});
    expect(body.headInLiquid, isTrue);
    expect(body.wading, isFalse);
  });

  test('a noclip body moves through stone', () {
    body
      ..noclip = true
      ..position = Vector3(4.5, 5.0, 4.5)
      ..velocity = Vector3(10, 0, 0);
    body.move(0.5);
    expect(body.position.x, closeTo(9.5, 1e-9));
  });

  test('the solid ray hits the floor from above through the top face; glass is solid, water is not', () {
    world.cells[const IVec3(2, 12, 2)] = _water;
    final hit = VoxelRaycast.solid(world, Vector3(2.5, 15.5, 2.5), Vector3(0, -1, 0), 10)!;
    expect(hit.block, const IVec3(2, 9, 2));
    expect(hit.normal, IVec3.up);
    expect(hit.distance, closeTo(5.5, 1e-9));

    world.cells[const IVec3(5, 12, 2)] = _glass;
    expect(VoxelRaycast.solid(world, Vector3(2.5, 12.5, 2.5), Vector3(1, 0, 0), 10)!.block, const IVec3(5, 12, 2));
    expect(VoxelRaycast.solid(world, Vector3(2.5, 15.5, 2.5), Vector3(0, 1, 0), 10), isNull);
  });

  test('the liquid ray finds water and stops at the first solid', () {
    world.cells[const IVec3(2, 10, 2)] = _water;
    expect(VoxelRaycast.liquid(world, Vector3(2.5, 13.5, 2.5), Vector3(0, -1, 0), 10), const IVec3(2, 10, 2));
    expect(VoxelRaycast.liquid(world, Vector3(6.5, 13.5, 6.5), Vector3(0, -1, 0), 10), isNull);
  });
}
