import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

const int _stone = 1, _water = 2, _lava = 3, _fence = 4, _mud = 5;

final _table = VoxelBlockTable(const [
  VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.5),
  VoxelBlockDef(
    shape: BlockShape.liquid,
    solid: false,
    opaque: false,
    r: 0.2,
    g: 0.4,
    b: 0.8,
    a: 0.6,
    liquidKind: 0,
    liquidSource: true,
  ),
  VoxelBlockDef(
    shape: BlockShape.liquid,
    solid: false,
    opaque: false,
    r: 0.9,
    g: 0.3,
    b: 0.1,
    liquidKind: 1,
    liquidSource: true,
  ),
  VoxelBlockDef(shape: BlockShape.fence, solid: true, opaque: false, r: 0.4, g: 0.3, b: 0.2),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.3, g: 0.2, b: 0.1),
]);

/// Stone up to y 9 everywhere, plus placed cells; the floor is y 10.
class _World implements VoxelQuery {
  final Map<IVec3, int> cells = {};

  @override
  VoxelBlockTable get table => _table;

  @override
  int getBlockXYZ(int x, int y, int z) => cells[IVec3(x, y, z)] ?? (y < 10 ? _stone : 0);
}

final PathCosts _noLava = PathCosts(avoid: (b) => b == _lava, floorCost: (b) => b == _mud ? 2.0 : 1.0);

void main() {
  test('a straight walk on a flat floor ends on the goal, one cell a step', () {
    final path = Pathfinder.find(_World(), const IVec3(0, 10, 0), const IVec3(5, 10, 0));
    expect(path, hasLength(5));
    expect(path.last.x, 5.5);
    expect(path.last.y, 10.0);
  });

  test('a wall two high is walked around; a one-high step is climbed', () {
    final w = _World();
    for (var z = -2; z <= 2; z++) {
      w.cells[IVec3(3, 10, z)] = _stone;
      w.cells[IVec3(3, 11, z)] = _stone;
    }
    final around = Pathfinder.find(w, const IVec3(0, 10, 0), const IVec3(6, 10, 0));
    expect(around.last.x, 6.5);
    expect(around.every((p) => p.x != 3.5 || p.z.abs() > 2), isTrue);

    final step = _World()..cells[const IVec3(3, 10, 0)] = _stone;
    final up = Pathfinder.find(step, const IVec3(0, 10, 0), const IVec3(3, 11, 0));
    expect(up.last.y, 11.0);
  });

  test('the policy decides: lava is never entered, a slow floor is walked around', () {
    final w = _World();
    for (var z = -1; z <= 1; z++) {
      w.cells[IVec3(2, 9, z)] = _lava;
      w.cells[IVec3(2, 10, z)] = _lava;
    }
    final plain = Pathfinder.find(w, const IVec3(0, 10, 0), const IVec3(4, 10, 0));
    expect(plain.any((p) => p.x == 2.5 && p.z == 0.5), isTrue, reason: 'lava is only a liquid to the plain policy');
    final careful = Pathfinder.find(w, const IVec3(0, 10, 0), const IVec3(4, 10, 0), costs: _noLava);
    expect(careful.last.x, 4.5);
    expect(careful.any((p) => p.x == 2.5 && p.z.floor() >= -1 && p.z.floor() <= 1), isFalse);

    final mud = _World();
    for (var x = 1; x <= 5; x++) {
      mud.cells[IVec3(x, 9, 0)] = _mud;
    }
    final detour = Pathfinder.find(mud, const IVec3(0, 10, 0), const IVec3(6, 10, 0), costs: _noLava);
    expect(
      detour.where((p) => p.z == 0.5 && p.x > 0.5 && p.x < 5.5),
      isEmpty,
      reason: 'two cells around are cheaper than five in mud',
    );
  });

  test('a fence top is no floor, and water costs more than land', () {
    final w = _World()..cells[const IVec3(2, 10, 0)] = _fence;
    expect(Pathfinder.walkable(w, const IVec3(2, 11, 0)), isFalse);
    final pool = _World();
    for (var x = 1; x <= 3; x++) {
      pool.cells[IVec3(x, 9, 0)] = _water;
    }
    expect(Pathfinder.walkable(pool, const IVec3(2, 9, 0)), isTrue, reason: 'a swimmer stands in water');
  });

  test('far from the origin, and one search after another, the paths are the same', () {
    final w = _World();
    for (var z = -2; z <= 2; z++) {
      w.cells[IVec3(-50003, 10, z - 70001)] = _stone;
      w.cells[IVec3(-50003, 11, z - 70001)] = _stone;
    }
    const from = IVec3(-50006, 10, -70001), to = IVec3(-50000, 10, -70001);
    final first = Pathfinder.find(w, from, to);
    expect(first.last.x, -50000 + 0.5);
    expect(first.every((p) => p.x != -50003 + 0.5 || (p.z.floor() + 70001).abs() > 2), isTrue);
    Pathfinder.find(w, const IVec3(0, 10, 0), const IVec3(9, 10, 3)); // another search between
    final again = Pathfinder.find(w, from, to);
    expect([for (final p in again) p.storage.toList()], [for (final p in first) p.storage.toList()]);
  });

  test('a policy that searches again from its callback is a mistake', () {
    final w = _World();
    late PathCosts nested;
    nested = PathCosts(
      avoid: (b) {
        Pathfinder.find(w, const IVec3(0, 10, 0), const IVec3(1, 10, 0), costs: nested);
        return false;
      },
    );
    expect(() => Pathfinder.find(w, const IVec3(0, 10, 0), const IVec3(3, 10, 0), costs: nested), throwsStateError);
    expect(
      Pathfinder.find(w, const IVec3(0, 10, 0), const IVec3(3, 10, 0)),
      hasLength(3),
      reason: 'the next search runs',
    );
  });

  test('an unreachable goal returns the best partial path toward it', () {
    final w = _World();
    for (var z = -20; z <= 20; z++) {
      for (var y = 10; y < 14; y++) {
        w.cells[IVec3(5, y, z)] = _stone;
      }
    }
    final path = Pathfinder.find(w, const IVec3(0, 10, 0), const IVec3(9, 10, 0), maxNodes: 200);
    expect(path, isNotEmpty);
    expect(path.last.x, 4.5);
  });
}
