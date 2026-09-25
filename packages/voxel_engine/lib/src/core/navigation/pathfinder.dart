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
///
/// A search keys its cells by an int (the offset from its start, packed) and
/// keeps its nodes in lists it reuses from one [find] to the next: a search
/// allocates nothing per cell it opens but the map's own entries.
class Pathfinder {
  /// The deepest drop a walker takes onto a landing.
  static const int maxDrop = 3;

  /// The expansion budget of one [find].
  static const int defaultMaxNodes = 600;

  static const List<int> _dx = [1, -1, 0, 0];
  static const List<int> _dz = [0, 0, 1, -1];

  /// Bits per axis of a cell's key; an offset from the start fits in ±[_half].
  static const int _bits = 12;
  static const int _half = 1 << (_bits - 1);
  static const int _mask = (1 << _bits) - 1;

  static final _Search _search = _Search();

  /// Cell centres (x + 0.5, y, z + 0.5) from the first step after [from] to the
  /// goal, or the partial path; empty when [from] has nowhere to go.
  static List<Vector3> find(VoxelQuery world, IVec3 from, IVec3 to,
      {PathCosts costs = PathCosts.plain, int maxNodes = defaultMaxNodes, bool canJump = true}) {
    // A path is no longer than the expansions it took, so every cell's offset fits.
    assert(maxNodes < _half - maxDrop, 'maxNodes $maxNodes does not fit a key of $_bits bits an axis');
    return _search.run(world, from, to, costs, maxNodes, canJump);
  }

  /// Whether a walker can stand in [c]: two free cells, neither avoided, over
  /// a solid floor that is not a fence (a fence is a barrier, never a floor)
  /// or in a liquid.
  static bool walkable(VoxelQuery w, IVec3 c, [PathCosts costs = PathCosts.plain]) => _walkable(w, costs, c.x, c.y, c.z);

  static bool _walkable(VoxelQuery w, PathCosts costs, int x, int y, int z) {
    final t = w.table;
    final feet = w.getBlockXYZ(x, y, z);
    final head = w.getBlockXYZ(x, y + 1, z);
    if (y < 0 || t.isSolid(feet) || t.isSolid(head)) return false;
    if (costs.avoid(feet) || costs.avoid(head)) return false;
    final below = w.getBlockXYZ(x, y - 1, z);
    return ((y - 1 < 0 || t.isSolid(below)) && t.shapeOf(below) != BlockShape.fence) || t.isLiquid(feet);
  }

  static bool _solid(VoxelQuery w, int x, int y, int z) => y < 0 || w.table.isSolid(w.getBlockXYZ(x, y, z));

  static int _h(int x, int y, int z, IVec3 to) => (x - to.x).abs() + (y - to.y).abs() + (z - to.z).abs();
}

/// One search's nodes, reused by the next: a node is an index into the lists,
/// found by its cell's key in [_index].
class _Search {
  final Map<int, int> _index = {};
  final List<int> _keys = [];
  final List<double> _g = [];
  final List<int> _parent = [];
  final List<bool> _closed = [];
  final _Heap _open = _Heap();
  bool _running = false;

  late int _fx, _fy, _fz;

  int _key(int x, int y, int z) =>
      ((x - _fx + Pathfinder._half) << (2 * Pathfinder._bits)) |
      ((y - _fy + Pathfinder._half) << Pathfinder._bits) |
      (z - _fz + Pathfinder._half);

  int _x(int key) => _fx + ((key >> (2 * Pathfinder._bits)) & Pathfinder._mask) - Pathfinder._half;
  int _y(int key) => _fy + ((key >> Pathfinder._bits) & Pathfinder._mask) - Pathfinder._half;
  int _z(int key) => _fz + (key & Pathfinder._mask) - Pathfinder._half;

  int _node(int key, double g, int parent) {
    final i = _keys.length;
    _keys.add(key);
    _g.add(g);
    _parent.add(parent);
    _closed.add(false);
    _index[key] = i;
    return i;
  }

  List<Vector3> run(VoxelQuery world, IVec3 from, IVec3 to, PathCosts costs, int maxNodes, bool canJump) {
    if (_running) throw StateError('Pathfinder.find re-entered from a PathCosts callback');
    _running = true;
    try {
      return _run(world, from, to, costs, maxNodes, canJump);
    } finally {
      _running = false;
    }
  }

  List<Vector3> _run(VoxelQuery world, IVec3 from, IVec3 to, PathCosts costs, int maxNodes, bool canJump) {
    _index.clear();
    _keys.clear();
    _g.clear();
    _parent.clear();
    _closed.clear();
    _open.clear();
    _fx = from.x;
    _fy = from.y;
    _fz = from.z;
    final root = _node(_key(from.x, from.y, from.z), 0.0, -1);
    final fromH = Pathfinder._h(from.x, from.y, from.z, to).toDouble();
    _open.push(fromH, 0.0, root);
    var best = root;
    var bestH = fromH;
    var bestG = 0.0;
    var expanded = 0;
    while (_open.isNotEmpty && expanded < maxNodes) {
      final cur = _open.pop();
      if (_closed[cur]) continue;
      _closed[cur] = true;
      expanded += 1;
      final key = _keys[cur];
      final cx = _x(key), cy = _y(key), cz = _z(key);
      if (cx == to.x && cy == to.y && cz == to.z) {
        best = cur;
        break;
      }
      final curG = _g[cur];
      final curH = Pathfinder._h(cx, cy, cz, to).toDouble();
      if (curH < bestH || (curH == bestH && curG < bestG)) {
        best = cur;
        bestH = curH;
        bestG = curG;
      }
      for (var d = 0; d < 4; d++) {
        final nx = cx + Pathfinder._dx[d], nz = cz + Pathfinder._dz[d];
        final sy = _stepTo(world, costs, cx, cy, cz, nx, nz, canJump);
        if (sy == null) continue;
        final ng = curG + _cost(world, costs, nx, sy, nz) + (sy - cy).abs() * 0.5;
        final step = _key(nx, sy, nz);
        var i = _index[step];
        if (i == null) {
          i = _node(step, ng, cur);
        } else {
          if (ng >= _g[i]) continue;
          _g[i] = ng;
          _parent[i] = cur;
        }
        _open.push(ng + Pathfinder._h(nx, sy, nz, to), ng, i);
      }
    }
    var n = 0;
    for (var walk = best; _parent[walk] >= 0; walk = _parent[walk]) {
      n += 1;
    }
    final path = List<Vector3>.filled(n, Vector3.zero());
    var walk = best;
    for (var k = n - 1; k >= 0; k--) {
      final key = _keys[walk];
      path[k] = Vector3(_x(key) + 0.5, _y(key).toDouble(), _z(key) + 0.5);
      walk = _parent[walk];
    }
    return path;
  }

  /// The y a walker standing in (cx, cy, cz) ends at when it moves to the
  /// column (nx, nz): level, one up, a landing below, or null when nothing
  /// there can be stood on.
  static int? _stepTo(VoxelQuery w, PathCosts costs, int cx, int cy, int cz, int nx, int nz, bool canJump) {
    if (Pathfinder._walkable(w, costs, nx, cy, nz)) return cy;
    if (canJump && !Pathfinder._solid(w, cx, cy + 2, cz) && Pathfinder._walkable(w, costs, nx, cy + 1, nz)) return cy + 1;
    if (Pathfinder._solid(w, nx, cy, nz) || Pathfinder._solid(w, nx, cy + 1, nz) || costs.avoid(w.getBlockXYZ(nx, cy, nz))) {
      return null;
    }
    for (var k = 1; k <= Pathfinder.maxDrop; k++) {
      final my = cy - k;
      if (Pathfinder._walkable(w, costs, nx, my, nz)) return my;
      if (Pathfinder._solid(w, nx, my, nz) || costs.avoid(w.getBlockXYZ(nx, my, nz))) return null;
    }
    return null;
  }

  static double _cost(VoxelQuery w, PathCosts costs, int x, int y, int z) {
    if (w.table.isLiquid(w.getBlockXYZ(x, y, z))) return costs.liquidCost;
    return costs.floorCost(w.getBlockXYZ(x, y - 1, z));
  }
}

/// A binary min-heap of node indices on f, then g (so equal f prefers the
/// deeper node).
class _Heap {
  final List<double> _f = [];
  final List<double> _g = [];
  final List<int> _nodes = [];

  bool get isNotEmpty => _nodes.isNotEmpty;

  void clear() {
    _f.clear();
    _g.clear();
    _nodes.clear();
  }

  bool _less(int i, int j) => _f[i] < _f[j] || (_f[i] == _f[j] && _g[i] > _g[j]);

  void _swap(int i, int j) {
    final f = _f[i];
    _f[i] = _f[j];
    _f[j] = f;
    final g = _g[i];
    _g[i] = _g[j];
    _g[j] = g;
    final c = _nodes[i];
    _nodes[i] = _nodes[j];
    _nodes[j] = c;
  }

  void push(double f, double g, int node) {
    _f.add(f);
    _g.add(g);
    _nodes.add(node);
    var i = _nodes.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (!_less(i, parent)) break;
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    final top = _nodes[0];
    final last = _nodes.length - 1;
    _swap(0, last);
    _f.removeLast();
    _g.removeLast();
    _nodes.removeLast();
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
