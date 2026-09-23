import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

const _air = VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0);
const _stone = VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.52);
const _water = VoxelBlockDef(
    shape: BlockShape.liquid, solid: false, opaque: false, r: 0.2, g: 0.42, b: 0.78, a: 0.62, liquidKind: 0, liquidSource: true);
const _waterFlow = VoxelBlockDef(
    shape: BlockShape.liquid, solid: false, opaque: false, r: 0.2, g: 0.42, b: 0.78, a: 0.62, liquidKind: 0);
const _lamp = VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.98, g: 0.88, b: 0.5, emission: 15);
const _slab = VoxelBlockDef(shape: BlockShape.slab, solid: true, opaque: false, r: 0.7, g: 0.5, b: 0.3);

void main() {
  final table = VoxelBlockTable(const [_air, _stone, _water, _waterFlow, _lamp, _slab]);

  test('the typed arrays hold one entry per id, in id order', () {
    expect(table.count, 6);
    expect(table.palette, hasLength(24));
    expect(table.palette.sublist(4, 8), Float32List.fromList([0.5, 0.5, 0.52, 1.0]));
    expect(table.shapes, [0, 0, BlockShape.liquid.index, BlockShape.liquid.index, 0, BlockShape.slab.index]);
    expect(table.opaque, [0, 1, 0, 0, 1, 0]);
    expect(table.emission, [0, 0, 0, 0, 15, 0]);
  });

  test('queries read the definitions', () {
    expect(table.isSolid(1), isTrue);
    expect(table.isOpaque(5), isFalse);
    expect(table.emissionOf(4), 15);
    expect(table.collisionBoxes(0), isEmpty);
    expect(table.collisionBoxes(5).single.y1, 0.5);
    expect(table.isLiquid(2) && table.isLiquid(3), isTrue);
    expect(table.isLiquidSource(2), isTrue);
    expect(table.isLiquidSource(3), isFalse);
    expect(table.liquidKind(3), 0);
    expect(table.liquidKind(1), VoxelBlockDef.noLiquid);
  });

  test('its mesher draws with its arrays', () {
    final c = Uint8List(ChunkSize.volume)..[ChunkSize.index(8, 40, 8)] = 4;
    final r = table.mesher().build(0, 0, [c, ...ChunkMesher.noNeighbours]);
    expect(r.glow.faceCount, 6, reason: 'emission 15 >= the glow threshold');
  });

  test('refuses a table a chunk byte cannot index or whose id 0 is not air', () {
    expect(() => VoxelBlockTable(const []), throwsArgumentError);
    expect(() => VoxelBlockTable(List.filled(257, _air)), throwsArgumentError);
    expect(() => VoxelBlockTable(const [_stone]), throwsArgumentError);
    expect(
        () => VoxelBlockTable(const [
              _air,
              VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 1, g: 1, b: 1, emission: 16),
            ]),
        throwsArgumentError);
    expect(
        () => VoxelBlockTable(const [
              _air,
              VoxelBlockDef(shape: BlockShape.liquid, solid: false, opaque: false, r: 1, g: 1, b: 1, liquidSource: true),
            ]),
        throwsArgumentError);
  });
}
