import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/signals.dart';

const int _stone = 1, _wireOff = 2, _wireOn = 3, _leverOff = 4, _leverOn = 5, _lampOff = 6, _lampOn = 7;
const int _button = 8, _buttonOn = 9, _railNs = 10, _railEw = 11, _railNe = 12, _railNw = 13, _railSe = 14, _railSw = 15;
const int _slopeN = 16, _slopeE = 17, _slopeS = 18, _slopeW = 19;

final _table = VoxelBlockTable([
  const VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  const VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.5),
  for (var i = 2; i < 20; i++) const VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0.5, g: 0.2, b: 0.2),
]);

/// A stone floor below y 10; every edit reaches the network, as a game's does.
class _World implements VoxelEditor {
  final Map<IVec3, int> cells = {};
  SignalNetwork? net;

  @override
  VoxelBlockTable get table => _table;

  @override
  int getBlockXYZ(int x, int y, int z) => cells[IVec3(x, y, z)] ?? (y < 10 ? _stone : 0);

  @override
  bool setBlock(IVec3 cell, int id) {
    final old = getBlockXYZ(cell.x, cell.y, cell.z);
    cells[cell] = id;
    net?.touch(cell, old, id);
    return true;
  }

  int at(int x, int y, int z) => getBlockXYZ(x, y, z);
}

SignalNetwork _network(_World w) => w.net = SignalNetwork(
      w,
      SignalRules(
        wireOff: _wireOff,
        wireOn: _wireOn,
        sources: const {_leverOn, _buttonOn},
        toggles: const {_leverOff: _leverOn, _leverOn: _leverOff},
        buttons: const {_button: (pressed: _buttonOn, seconds: 1.0)},
        reactions: {_lampOff: SignalReactions.swap(_lampOff, _lampOn), _lampOn: SignalReactions.swap(_lampOff, _lampOn)},
      ),
    );

void _run(SignalNetwork n, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    n.tick(1 / 60);
  }
}

void main() {
  test('a lever powers a wire that decays by one a cell and lights a lamp', () {
    final w = _World();
    final net = _network(w);
    w.setBlock(const IVec3(0, 10, 0), _leverOff);
    for (var x = 1; x <= 5; x++) {
      w.setBlock(IVec3(x, 10, 0), _wireOff);
    }
    w.setBlock(const IVec3(6, 10, 0), _lampOff);
    _run(net, 0.2);
    expect(w.at(6, 10, 0), _lampOff);
    expect(net.use(const IVec3(0, 10, 0)), isTrue);
    _run(net, 0.2);
    expect([for (var x = 1; x <= 5; x++) net.strengthAt(IVec3(x, 10, 0))], [15, 14, 13, 12, 11]);
    expect(w.at(3, 10, 0), _wireOn);
    expect(w.at(6, 10, 0), _lampOn);
    net.use(const IVec3(0, 10, 0));
    _run(net, 0.2);
    expect(w.at(6, 10, 0), _lampOff);
    expect(net.strengthAt(const IVec3(1, 10, 0)), 0);
  });

  test('power runs out after fifteen cells; a wire climbs a step', () {
    final w = _World();
    final net = _network(w);
    w.setBlock(const IVec3(0, 10, 0), _leverOn);
    for (var x = 1; x <= 17; x++) {
      w.setBlock(IVec3(x, 10, 0), _wireOff);
    }
    w.setBlock(const IVec3(18, 10, 0), _stone);
    w.setBlock(const IVec3(18, 11, 0), _wireOff);
    _run(net, 0.2);
    expect(net.strengthAt(const IVec3(15, 10, 0)), 1);
    expect(net.strengthAt(const IVec3(16, 10, 0)), 0);
    final short = _World();
    final n2 = _network(short);
    short.setBlock(const IVec3(0, 10, 0), _leverOn);
    short.setBlock(const IVec3(1, 10, 0), _wireOff);
    short.setBlock(const IVec3(2, 10, 0), _stone);
    short.setBlock(const IVec3(2, 11, 0), _wireOff);
    _run(n2, 0.2);
    expect(n2.strengthAt(const IVec3(2, 11, 0)), 14, reason: 'up one along the edge');
  });

  test('a button powers for its seconds, then lets go', () {
    final w = _World();
    final net = _network(w);
    w.setBlock(const IVec3(0, 10, 0), _button);
    w.setBlock(const IVec3(1, 10, 0), _lampOff);
    net.use(const IVec3(0, 10, 0));
    _run(net, 0.3);
    expect(w.at(1, 10, 0), _lampOn);
    _run(net, 1.0);
    expect(w.at(0, 10, 0), _button);
    expect(w.at(1, 10, 0), _lampOff);
  });

  group('RailGraph', () {
    final graph = RailGraph({
      _railNs: const RailVariant('rail', 'ns'),
      _railEw: const RailVariant('rail', 'ew'),
      _railNe: const RailVariant('rail', 'ne'),
      _railNw: const RailVariant('rail', 'nw'),
      _railSe: const RailVariant('rail', 'se'),
      _railSw: const RailVariant('rail', 'sw'),
      _slopeN: const RailVariant('rail', 'slope_n'),
      _slopeE: const RailVariant('rail', 'slope_e'),
      _slopeS: const RailVariant('rail', 'slope_s'),
      _slopeW: const RailVariant('rail', 'slope_w'),
    });

    test('a line of rails lays straight, a corner curves, a step up slopes', () {
      final w = _World();
      graph.place(w, const IVec3(0, 10, 0), _railNs);
      graph.place(w, const IVec3(1, 10, 0), _railNs);
      expect(w.at(0, 10, 0), _railEw, reason: 'turned to meet its neighbour');
      expect(w.at(1, 10, 0), _railEw);
      graph.place(w, const IVec3(1, 10, 1), _railNs);
      expect(w.at(1, 10, 0), _railSw, reason: 'west and south: a curve');
      final hill = _World();
      hill.setBlock(const IVec3(1, 10, 0), _stone);
      graph.place(hill, const IVec3(1, 11, 0), _railNs);
      graph.place(hill, const IVec3(0, 10, 0), _railNs);
      expect(hill.at(0, 10, 0), _slopeE, reason: 'the rail up east on a block: a slope climbing east');
    });

    test('a cart walks the line and stops at its end', () {
      final w = _World();
      for (var x = 0; x < 4; x++) {
        graph.place(w, IVec3(x, 10, 0), _railNs);
      }
      var cell = const IVec3(0, 10, 0);
      var steps = 0;
      while (steps < 10) {
        final next = graph.nextCell(w, cell, const IVec3(1, 0, 0));
        if (next == cell) break;
        cell = next;
        steps++;
      }
      expect(cell, const IVec3(3, 10, 0));
      expect(graph.endToward(w, const IVec3(2, 10, 0), const IVec3(1, 10, 0)), const IVec3(-1, 0, 0));
    });
  });
}
