import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

void main() {
  test('a chunk volume is 16 x 16 x 128, indexed x within z within y', () {
    expect(ChunkSize.volume, 32768);
    expect(ChunkSize.index(0, 0, 0), 0);
    expect(ChunkSize.index(1, 0, 0), 1);
    expect(ChunkSize.index(0, 0, 1), 16);
    expect(ChunkSize.index(0, 1, 0), 256);
    expect(ChunkSize.index(15, 127, 15), ChunkSize.volume - 1);
  });

  test('the shape order is the byte contract the mesher reads', () {
    expect(BlockShape.values, hasLength(26));
    expect(BlockShape.cube.index, 0);
    expect(BlockShape.liquid.index, 2);
    expect(BlockShape.slab.index, 8);
    expect(BlockShape.wire.index, 14);
    expect(BlockShape.railSlopeW.index, 24);
    expect(BlockShape.ladder.index, 25);
  });

  test('a block that stops no body has no boxes, whatever its shape', () {
    for (final shape in BlockShape.values) {
      expect(collisionBoxesOf(shape, solid: false), isEmpty, reason: '$shape');
    }
  });

  test('solid shapes: full cell, half slab, one-block fence post, two-box stairs', () {
    expect(collisionBoxesOf(BlockShape.cube, solid: true), [same(CollisionBox.full)]);
    expect(collisionBoxesOf(BlockShape.slab, solid: true).single.y1, 0.5);
    expect(collisionBoxesOf(BlockShape.fence, solid: true).single.y1, 1.0);
    final n = collisionBoxesOf(BlockShape.stairsN, solid: true);
    expect(n, hasLength(2));
    expect([n[1].z0, n[1].z1], [0.0, 0.5]);
    final e = collisionBoxesOf(BlockShape.stairsE, solid: true);
    expect([e[1].x0, e[1].x1], [0.5, 1.0]);
  });

  test('a box shifts into world space and reads min / max per axis', () {
    final b = CollisionBox.fencePost.shifted(3, -1, 7);
    expect([b.min(0), b.min(1), b.min(2)], [3.375, -1.0, 7.375]);
    expect([b.max(0), b.max(1), b.max(2)], [3.625, 0.0, 7.625]);
  });
}
