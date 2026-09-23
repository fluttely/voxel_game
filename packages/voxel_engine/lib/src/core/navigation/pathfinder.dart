import 'package:vector_math/vector_math.dart';

import '../grid/block_shape.dart';
import '../math/ivec3.dart';
import '../physics/voxel_body.dart';

/// What a path may cross and what each cell costs, the game's say in
/// [Pathfinder]. The engine knows solids, liquids and fences from the block
/// table; which liquid burns and which floor is slow is the game's.
class PathCosts {
  /// A policy: never enter a cell where [avoid] is true, pay [liquidCost] for a
  /// liquid cell and [floorCost] of the block under the feet for any other.
  const PathCosts({this.avoid = _never, this.liquidCost = 3.0, this.floorCost = _one});

  /// Every cell costs 1, liquids 3, nothing is avoided.
  static const PathCosts plain = PathCosts();

  /// True for a block no path may enter, at the feet or at the head (lava).
  final bool Function(int block) avoid;

  /// The cost of a step into a liquid cell.
  final double liquidCost;

  /// The cost of a step onto a cell standing on [floor] (2 for a floor that
  /// halves a walker's speed).
  final double Function(int floor) floorCost;

  static bool _never(int block) => false;
  static double _one(int floor) => 1.0;
}

/// A* on the block grid for walking creatures. A node is a feet cell (air, air
/// above, something to stand on below, never a fence top); the moves are the
/// four horizontal steps, a step up of one (with head room) and a drop of up
/// to [maxDrop] onto a landing. The heuristic is the Manhattan distance. At
/// most `maxNodes` expansions per call; when the goal is not reached the best
/// partial path toward it is returned (the node closest by heuristic, ties on
/// the lower cost). Below y 0 counts as solid.
class Pathfinder {
  /// The deepest drop a walker takes onto a landing.
  static const int maxDrop = 3;

  /// The expansion budget of one [find].
  static const int defaultMaxNodes = 600;
  static const List<IVec3> _four = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)];

  /// Cell centres (x + 0.5, y, z + 0.5) from the first step after [from] to the
  /// goal, or the partial path; empty when [from] has nowhere to go.
  static List<Vector3> find(VoxelQuery world, IVec3 from, IVec3 to,
      {PathCosts costs = PathCosts.plain, int maxNodes = defaultMaxNodes, bool canJump = true}) {
    final gScore = <IVec3, double>{from: 0.0};
    final cameFrom = <IVec3, IVec3>{};
    final closed = <IVec3>{};
    final open = _Heap()..push(_h(from, to), 0.0, from);
    var best = from;
    var bestH = _h(from, to);
    var bestG = 0.0;
    var expanded = 0;
    while (open.isNotEmpty && expanded < maxNodes) {
      final cur = open.pop();
      if (!closed.add(cur)) continue;
      expanded += 1;
      if (cur == to) {
        best = cur;
        break;
      }
      final curG = gScore[cur]!;
      final curH = _h(cur, to);
      if (curH < bestH || (curH == bestH && curG < bestG)) {
        best = cur;
        bestH = curH;
        bestG = curG;
      }
      for (final d in _four) {
        final step = _stepTo(world, costs, cur, cur + d, canJump);
        if (step == null) continue;
        final ng = curG + _cost(world, costs, step) + (step.y - cur.y).abs() * 0.5;
        if (ng >= (gScore[step] ?? double.infinity)) continue;
        gScore[step] = ng;
        cameFrom[step] = cur;
        open.push(ng + _h(step, to), ng, step);
      }
    }
    final cells = <IVec3>[];
    var walk = best;
    while (cameFrom.containsKey(walk)) {
      cells.add(walk);
      walk = cameFrom[walk]!;
    }
    return [for (final c in cells.reversed) Vector3(c.x + 0.5, c.y.toDouble(), c.z + 0.5)];
  }

  /// Where a walker standing in [cur] ends up when it moves toward the column of
  /// [n]: [n] itself, one up, a landing below, or null when nothing there can be
  /// stood on.
  static IVec3? _stepTo(VoxelQuery w, PathCosts costs, IVec3 cur, IVec3 n, bool canJump) {
    if (walkable(w, n, costs)) return n;
    if (canJump && !_solid(w, cur + const IVec3(0, 2, 0)) && walkable(w, n + IVec3.up, costs)) return n + IVec3.up;
    if (_solid(w, n) || _solid(w, n + IVec3.up) || _avoided(w, costs, n)) return null;
    for (var k = 1; k <= maxDrop; k++) {
      final m = n - IVec3(0, k, 0);
      if (walkable(w, m, costs)) return m;
      if (_solid(w, m) || _avoided(w, costs, m)) return null;
    }
    return null;
  }

  /// Whether a walker can stand in [c]: two free cells, neither avoided, over
  /// a solid floor that is not a fence (a fence is a barrier, never a floor)
  /// or in a liquid.
  static bool walkable(VoxelQuery w, IVec3 c, [PathCosts costs = PathCosts.plain]) {
    if (_solid(w, c) || _solid(w, c + IVec3.up)) return false;
    if (_avoided(w, costs, c) || _avoided(w, costs, c + IVec3.up)) return false;
    final below = _block(w, c + IVec3.down);
    return (_solid(w, c + IVec3.down) && w.table.shapeOf(below) != BlockShape.fence) || w.table.isLiquid(_block(w, c));
  }

  static int _block(VoxelQuery w, IVec3 c) => w.getBlockXYZ(c.x, c.y, c.z);

  static bool _solid(VoxelQuery w, IVec3 c) => c.y < 0 || w.table.isSolid(_block(w, c));

  static bool _avoided(VoxelQuery w, PathCosts costs, IVec3 c) => costs.avoid(_block(w, c));

  static double _cost(VoxelQuery w, PathCosts costs, IVec3 c) {
    if (w.table.isLiquid(_block(w, c))) return costs.liquidCost;
    return costs.floorCost(_block(w, c + IVec3.down));
  }

  static double _h(IVec3 a, IVec3 b) => ((a.x - b.x).abs() + (a.y - b.y).abs() + (a.z - b.z).abs()).toDouble();
}

/// A binary min-heap on f, then g (so equal f prefers the deeper node).
class _Heap {
  final List<double> _f = [];
  final List<double> _g = [];
  final List<IVec3> _cells = [];

  bool get isNotEmpty => _cells.isNotEmpty;

  bool _less(int i, int j) => _f[i] < _f[j] || (_f[i] == _f[j] && _g[i] > _g[j]);

  void _swap(int i, int j) {
    final f = _f[i];
    _f[i] = _f[j];
    _f[j] = f;
    final g = _g[i];
    _g[i] = _g[j];
    _g[j] = g;
    final c = _cells[i];
    _cells[i] = _cells[j];
    _cells[j] = c;
  }

  void push(double f, double g, IVec3 cell) {
    _f.add(f);
    _g.add(g);
    _cells.add(cell);
    var i = _cells.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (!_less(i, parent)) break;
      _swap(i, parent);
      i = parent;
    }
  }

  IVec3 pop() {
    final top = _cells[0];
    final last = _cells.length - 1;
    _swap(0, last);
    _f.removeLast();
    _g.removeLast();
    _cells.removeLast();
    var i = 0;
    while (true) {
      final l = i * 2 + 1;
      final r = l + 1;
      var m = i;
      if (l < last && _less(l, m)) m = l;
      if (r < last && _less(r, m)) m = r;
      if (m == i) break;
      _swap(i, m);
      i = m;
    }
    return top;
  }
}
