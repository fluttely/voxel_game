import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

const int _stone = 1, _water = 2, _waterFlow = 3, _lava = 4, _lavaFlow = 5, _cobble = 6;

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
    liquidKind: 0,
    liquidSource: true,
  ),
  VoxelBlockDef(shape: BlockShape.liquid, solid: false, opaque: false, r: 0.2, g: 0.4, b: 0.8, liquidKind: 0),
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
  VoxelBlockDef(shape: BlockShape.liquid, solid: false, opaque: false, r: 0.9, g: 0.3, b: 0.1, liquidKind: 1),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.4, g: 0.4, b: 0.4),
]);

/// A stone floor up to y 9; every edit goes through the flow, as a game's would.
class _World implements VoxelEditor {
  _World() {
    flow = LiquidFlow(
      table: _table,
      rules: const [
        LiquidRule(flowingId: _waterFlow, period: 0.25, reach: 4),
        LiquidRule(flowingId: _lavaFlow, period: 0.6, reach: 2),
      ],
      canEnter: (id) => id == VoxelBlockTable.air,
      contact: (kind, source, touching) => kind == 1 && touching == 0 ? _cobble : null,
    );
  }

  late final LiquidFlow flow;
  final Map<IVec3, int> cells = {};

  @override
  VoxelBlockTable get table => _table;

  @override
  int getBlockXYZ(int x, int y, int z) => cells[IVec3(x, y, z)] ?? (y < 10 ? _stone : 0);

  @override
  bool setBlock(IVec3 cell, int id) {
    final old = getBlockXYZ(cell.x, cell.y, cell.z);
    cells[cell] = id;
    flow.touch(this, cell, old, id);
    return true;
  }

  void run(double seconds) {
    for (var t = 0.0; t < seconds; t += 1 / 60) {
      flow.tick(this, 1 / 60);
    }
  }

  int count(int id) => cells.values.where((v) => v == id).length;
}

void main() {
  test('a water source on a floor spreads to its reach as a diamond', () {
    final w = _World()..setBlock(const IVec3(0, 10, 0), _water);
    w.run(5);
    // Cells within Manhattan distance 4 of the source, minus the source: 2*4*5 = 40.
    expect(w.count(_waterFlow), 40);
    expect(w.flow.distOf(const IVec3(4, 10, 0), -1), 4);
    expect(w.getBlockXYZ(5, 10, 0), VoxelBlockTable.air);
  });

  test('removing the source drains the puddle', () {
    final w = _World()..setBlock(const IVec3(0, 10, 0), _water);
    w.run(5);
    w.setBlock(const IVec3(0, 10, 0), VoxelBlockTable.air);
    w.run(10);
    expect(w.count(_waterFlow), 0);
    expect(w.flow.pending, 0);
  });

  test('a liquid falls before it spreads', () {
    final w = _World()..cells[const IVec3(0, 9, 0)] = VoxelBlockTable.air;
    w.cells[const IVec3(0, 8, 0)] = VoxelBlockTable.air;
    w.setBlock(const IVec3(0, 10, 0), _water);
    w.run(0.3);
    expect(w.getBlockXYZ(0, 9, 0), _waterFlow, reason: 'the first step goes down');
    expect(w.getBlockXYZ(1, 10, 0), VoxelBlockTable.air, reason: 'nothing sideways while it can fall');
  });

  test('the contact rule hardens lava beside water; a disabled flow does nothing', () {
    final w = _World()..setBlock(const IVec3(0, 10, 0), _water);
    w.run(2);
    w.setBlock(const IVec3(6, 10, 0), _lava);
    w.run(5);
    expect(w.count(_cobble), greaterThan(0));

    final idle = _World()..flow.enabled = false;
    idle.setBlock(const IVec3(0, 10, 0), _water);
    idle.run(2);
    expect(idle.count(_waterFlow), 0);
    expect(idle.flow.updates, 0);
  });
}
