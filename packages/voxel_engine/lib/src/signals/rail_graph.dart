import 'package:voxel_engine/core.dart';

/// One rail block: its [kind] (rails of a kind turn into one another), its
/// [shape] (`ns`, `ew`, `ne`, `nw`, `se`, `sw`, `slope_n`, `slope_e`,
/// `slope_s`, `slope_w`) and, for a kind that has two states, whether this is
/// the [on] one (a powered rail).
class RailVariant {
  /// A variant.
  const RailVariant(this.kind, this.shape, {this.on = false});

  /// The kind: `rail`, `powered_rail`.
  final String kind;

  /// The two ends it joins, by name.
  final String shape;

  /// The powered state of a two-state kind.
  final bool on;
}

/// Rails that lay themselves: which ends a rail joins, which rail a cell
/// should hold from what is around it, and how a cart walks the line.
///
/// A straight joins two opposite sides, a curve two adjacent ones, a slope
/// its low side on the same level and its high side one cell up. A kind
/// without slopes or curves (a powered rail) only lays straights.
class RailGraph {
  /// A graph over [variants] (block id to what it is).
  RailGraph(this.variants) {
    for (final e in variants.entries) {
      _byKey[_key(e.value.kind, e.value.shape, e.value.on)] = e.key;
    }
  }

  /// Every rail block, by id.
  final Map<int, RailVariant> variants;

  final Map<String, int> _byKey = {};

  static String _key(String kind, String shape, bool on) => '$kind/$shape/$on';

  /// North, -z.
  static const IVec3 n = IVec3(0, 0, -1);

  /// South, +z.
  static const IVec3 s = IVec3(0, 0, 1);

  /// East, +x.
  static const IVec3 e = IVec3(1, 0, 0);

  /// West, -x.
  static const IVec3 w = IVec3(-1, 0, 0);

  /// The four sides.
  static const List<IVec3> four = [n, e, s, w];

  /// Shape to its two ends; a slope's high end carries dy = +1.
  static const Map<String, List<IVec3>> ends = {
    'ns': [IVec3(0, 0, -1), IVec3(0, 0, 1)],
    'ew': [IVec3(1, 0, 0), IVec3(-1, 0, 0)],
    'ne': [IVec3(0, 0, -1), IVec3(1, 0, 0)],
    'nw': [IVec3(0, 0, -1), IVec3(-1, 0, 0)],
    'se': [IVec3(0, 0, 1), IVec3(1, 0, 0)],
    'sw': [IVec3(0, 0, 1), IVec3(-1, 0, 0)],
    'slope_n': [IVec3(0, 0, 1), IVec3(0, 1, -1)],
    'slope_e': [IVec3(-1, 0, 0), IVec3(1, 1, 0)],
    'slope_s': [IVec3(0, 0, -1), IVec3(0, 1, 1)],
    'slope_w': [IVec3(1, 0, 0), IVec3(-1, 1, 0)],
  };

  /// Whether [id] is a rail.
  bool isRail(int id) => variants.containsKey(id);

  /// Whether [id] is a sloped rail.
  bool isSlope(int id) => variants[id]?.shape.startsWith('slope') ?? false;

  /// The shape of rail [id].
  String shapeOf(int id) => variants[id]!.shape;

  /// The two ends rail [id] joins, as steps from its cell.
  List<IVec3> connections(int id) => ends[variants[id]!.shape]!;

  bool _has(String kind, String shape) =>
      _byKey.containsKey(_key(kind, shape, false)) || _byKey.containsKey(_key(kind, shape, true));

  /// The rail of [baseId]'s kind (and state) turned to [shape]; a kind that
  /// lacks the shape lays the straight nearest to it.
  int withShape(int baseId, String shape) {
    final v = variants[baseId]!;
    var sh = shape;
    if (!_has(v.kind, sh)) sh = sh.endsWith('n') || sh.endsWith('s') ? 'ns' : 'ew';
    return _byKey[_key(v.kind, sh, v.on)] ?? _byKey[_key(v.kind, sh, false)]!;
  }

  bool _railAt(VoxelQuery world, IVec3 c) => isRail(world.getBlockXYZ(c.x, c.y, c.z));

  int _at(VoxelQuery world, IVec3 c) => world.getBlockXYZ(c.x, c.y, c.z);

  static IVec3 _flat(IVec3 d) => IVec3(d.x, 0, d.z);

  static IVec3 _neg(IVec3 d) => IVec3(-d.x, -d.y, -d.z);

  /// `_n`, `_e`, `_s` or `_w`: the side a horizontal direction points to.
  static String facingSuffix(double x, double z) {
    if (x.abs() > z.abs()) return x > 0 ? '_e' : '_w';
    return z > 0 ? '_s' : '_n';
  }

  /// The cell a cart leaves [cell] into through [end], or [cell] itself when
  /// the line stops there. A flat end also reaches a slope one cell down whose
  /// high side climbs back toward [cell].
  IVec3 nextCell(VoxelQuery world, IVec3 cell, IVec3 end) {
    final c = cell + end;
    if (_railAt(world, c)) return c;
    if (end.y == 0) {
      final below = c + IVec3.down;
      final bid = _at(world, below);
      if (isRail(bid) && isSlope(bid)) {
        for (final e in connections(bid)) {
          if (e.y == 1 && _flat(e) == _neg(end)) return below;
        }
      }
    }
    return cell;
  }

  /// The end of the rail at [cell] pointing back toward [from], or
  /// [IVec3.zero] when that rail does not join [from].
  IVec3 endToward(VoxelQuery world, IVec3 cell, IVec3 from) {
    final id = _at(world, cell);
    if (!isRail(id)) return IVec3.zero;
    final back = _flat(from - cell);
    for (final e in connections(id)) {
      if (_flat(e) == back) return e;
    }
    return IVec3.zero;
  }

  /// The rail of [baseId]'s kind [cell] should hold, from the rails around
  /// it: one a cell up on a side (over a solid block) makes a slope toward
  /// it; two sides a straight or a curve (a through line wins, and the rails
  /// pointing at this cell come first); one side a straight along it; none
  /// keeps the axis the cell has (or north-south).
  int orient(VoxelQuery world, IVec3 cell, int baseId) {
    final strong = <IVec3>[];
    final weak = <IVec3>[];
    var up = IVec3.zero;
    for (final d in four) {
      final nb = cell + d;
      if (_railAt(world, nb)) {
        final nid = _at(world, nb);
        var facesUs = false;
        var climbsAway = false;
        for (final e in connections(nid)) {
          if (_flat(e) == _neg(d)) {
            facesUs = e.y == 0;
            climbsAway = e.y == 1;
          }
        }
        if (climbsAway) continue;
        if (facesUs) {
          strong.add(d);
        } else {
          weak.add(d);
        }
        continue;
      }
      final below = nb + IVec3.down;
      final bid = _at(world, below);
      if (isRail(bid) && isSlope(bid)) {
        for (final e in connections(bid)) {
          if (e.y == 1 && _flat(e) == _neg(d)) strong.add(d);
        }
      }
      final above = nb + IVec3.up;
      if (up == IVec3.zero && _railAt(world, above) && world.table.isSolid(_at(world, nb))) up = d;
    }
    final kind = variants[baseId]!.kind;
    if (up != IVec3.zero && _has(kind, 'slope_n')) {
      return withShape(baseId, 'slope${facingSuffix(up.x.toDouble(), up.z.toDouble())}');
    }
    final sides = [...strong, ...weak];
    if (sides.length >= 2) {
      if (sides.contains(n) && sides.contains(s)) return withShape(baseId, 'ns');
      if (sides.contains(e) && sides.contains(w)) return withShape(baseId, 'ew');
      final a = sides[0], b = sides[1];
      final zs = a.z < 0 || b.z < 0 ? 'n' : 's';
      final xs = a.x > 0 || b.x > 0 ? 'e' : 'w';
      return withShape(baseId, '$zs$xs');
    }
    if (sides.length == 1) return withShape(baseId, sides[0].z != 0 ? 'ns' : 'ew');
    final current = _at(world, cell);
    if (isRail(current)) {
      final sh = shapeOf(current);
      if (sh == 'ns' || sh == 'ew') return withShape(baseId, sh);
      return withShape(baseId, sh.endsWith('n') || sh.endsWith('s') ? 'ns' : 'ew');
    }
    return withShape(baseId, 'ns');
  }

  /// Every cell whose rail may change when [cell] does: the four sides, a
  /// cell up and a cell down on each.
  static List<IVec3> neighbours(IVec3 cell) => [
    for (final d in four) ...[cell + d, cell + d + IVec3.up, cell + d + IVec3.down],
  ];

  /// Re-orients the rail at [c], if there is one.
  void refresh(VoxelEditor world, IVec3 c) {
    final id = _at(world, c);
    if (!isRail(id)) return;
    final want = orient(world, c, id);
    if (want != id) world.setBlock(c, want);
  }

  /// Lays a rail of [baseId]'s kind at [cell], oriented by its neighbours,
  /// turns the neighbours to meet it, and orients it once more (a neighbour
  /// may just have become a slope toward it). Returns the id laid.
  int place(VoxelEditor world, IVec3 cell, int baseId) {
    world.setBlock(cell, orient(world, cell, baseId));
    for (final nb in neighbours(cell)) {
      refresh(world, nb);
    }
    refresh(world, cell);
    return _at(world, cell);
  }

  /// After the rail at [cell] went: the neighbours no longer lean on it.
  void removed(VoxelEditor world, IVec3 cell) {
    for (final nb in neighbours(cell)) {
      refresh(world, nb);
    }
  }
}
