import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

const int _stone = 1, _flower = 2;

final _table = VoxelBlockTable(const [
  VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.5),
  VoxelBlockDef(shape: BlockShape.cross, solid: false, opaque: false, r: 0.9, g: 0.2, b: 0.2),
]);

class _World implements VoxelQuery {
  final Map<IVec3, int> cells = {};

  @override
  VoxelBlockTable get table => _table;

  @override
  int getBlockXYZ(int x, int y, int z) => cells[IVec3(x, y, z)] ?? 0;
}

VoxelBody _bodyAt(_World w, double x) => VoxelBody()
  ..setup(w, 0.3, 1.8)
  ..position = Vector3(x, 10, 0.5);

void main() {
  final eye = Vector3(0.5, 11.5, 0.5), east = Vector3(1, 0, 0);

  test('the nearest body along the line wins, within reach', () {
    final w = _World();
    final near = _bodyAt(w, 3.5), far = _bodyAt(w, 4.5);
    expect(Reach.nearestBody([far, near], eye, east, maxDist: 5), same(near));
    expect(Reach.nearestBody([far, near], eye, east, maxDist: 2), isNull);
    expect(Reach.nearestBody([far, near], eye, east, maxDist: 5, accepts: (b) => b != near), same(far));
  });

  test('a block in front of a body hides it; a flower does not stop a swing', () {
    final w = _World()..cells[const IVec3(2, 11, 0)] = _stone;
    final mob = _bodyAt(w, 3.5);
    final wall = Reach.toBarrier(w, eye, east, 5);
    expect(wall, closeTo(1.5, 1e-6));
    expect(Reach.nearestBody([mob], eye, east, maxDist: 5, blockedAt: wall), isNull);

    w.cells[const IVec3(2, 11, 0)] = _flower;
    expect(Reach.toBlock(w, eye, east, 5), closeTo(1.5, 1e-6), reason: 'a flower is aimed at');
    expect(Reach.toBarrier(w, eye, east, 5), double.infinity, reason: 'but a swing crosses it');
  });
}
