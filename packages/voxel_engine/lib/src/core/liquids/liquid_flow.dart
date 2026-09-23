import 'dart:math' as math;

import '../grid/voxel_block_table.dart';
import '../math/ivec3.dart';
import '../physics/voxel_body.dart';

/// A world the flow can change as well as read.
abstract interface class VoxelEditor implements VoxelQuery {
  /// Writes [id] at [cell]; false when the cell cannot be written (its chunk
  /// is not loaded).
  bool setBlock(IVec3 cell, int id);
}

/// How one liquid kind flows.
class LiquidRule {
  /// A kind whose flowing cells are [flowingId], stepping every [period]
  /// seconds and spreading at most [reach] cells sideways from a source.
  const LiquidRule({required this.flowingId, required this.period, required this.reach});

  /// The block id the liquid writes where it flows (not a source).
  final int flowingId;

  /// Seconds between two steps of this kind.
  final double period;

  /// How many cells sideways a source feeds.
  final int reach;
}

/// What a liquid cell of `kind` (a source when `source`) becomes when it
/// touches a liquid of `touching` kind, or null when the two ignore each
/// other. Lava meeting water hardens this way.
typedef LiquidContact = int? Function(int kind, bool source, int touching);

/// Cellular liquid flow over a [VoxelEditor], driven by edits alone so an idle
/// world costs nothing: a generated lake is sources resting on solid and never
/// enters the queue until something next to it changes.
///
/// A liquid is any block with a liquid kind in the [VoxelBlockTable]; a kind's
/// sources are the blocks the table marks as sources, its flowing form is
/// [LiquidRule.flowingId]. The rules, each step:
/// - a flowing cell lives only while fed: by the same kind above, or by a
///   sideways neighbour strictly closer to a source (a sibling does not count,
///   so removing a source drains its puddle in order); otherwise it becomes air;
/// - a cell falls first, and a fall resets the distance;
/// - it spreads sideways only when resting on a solid block or a source, to at
///   most [LiquidRule.reach] cells;
/// - it enters only cells [canEnter] allows (air and plants, typically);
/// - [contact] decides what two kinds do when they touch.
///
/// Call [touch] from every block edit and [tick] once per simulation step.
class LiquidFlow {
  /// A flow over [table] with one [LiquidRule] per liquid kind index.
  LiquidFlow({
    required this.table,
    required this.rules,
    required this.canEnter,
    this.contact,
    this.budget = 400,
  }) : _timers = List<double>.filled(rules.length, 0.0);

  /// A flowing cell whose distance is not known (loaded from a save): it
  /// re-derives it when touched.
  static const int unknown = 99;

  static const List<IVec3> _six = [
    IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), //
  ];
  static const List<IVec3> _four = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)];

  /// What each block id is.
  final VoxelBlockTable table;

  /// The rule of each liquid kind, by kind index.
  final List<LiquidRule> rules;

  /// Whether a liquid may flow into a cell holding this block.
  final bool Function(int id) canEnter;

  /// What touching kinds do; null when kinds never react.
  final LiquidContact? contact;

  /// At most this many cells are stepped per [tick]; the rest wait.
  final int budget;

  /// False on a client: the host owns the flow and every cell it writes
  /// arrives as a plain edit. While false, [touch] and [tick] do nothing.
  bool enabled = true;

  /// Liquid cells to visit, in insertion order.
  Set<IVec3> _queue = <IVec3>{};

  /// Sideways steps from the feeding source (flowing cells only).
  final Map<IVec3, int> _dist = {};
  final List<double> _timers;

  /// Cells written by the flow since it was made.
  int get updates => _updates;
  int _updates = 0;

  /// Cells waiting to be stepped.
  int get pending => _queue.length;

  /// The recorded distance of [cell], or [fallback] when it has none.
  int distOf(IVec3 cell, [int fallback = 0]) => _dist[cell] ?? fallback;

  /// Forgets every queued cell and distance (a dimension change).
  void clear() {
    _queue.clear();
    _dist.clear();
  }

  /// Wakes the liquids around an edit at [cell] from [old] to [id]: the cell
  /// itself when it is one, and each liquid neighbour (a feeder that vanished,
  /// a wall that opened, two kinds now touching).
  void touch(VoxelQuery world, IVec3 cell, int old, int id) {
    if (!enabled) return;
    if (table.isLiquid(id)) {
      _queue.add(cell);
    } else if (table.isLiquid(old)) {
      _dist.remove(cell);
    }
    for (final d in _six) {
      final n = cell + d;
      if (table.isLiquid(world.getBlockXYZ(n.x, n.y, n.z))) _queue.add(n);
    }
  }

  /// Advances the flow by [dt] seconds, writing through [world]; the writes
  /// come back through [touch] as edits like any other.
  void tick(VoxelEditor world, double dt) {
    if (!enabled) return;
    if (_queue.isEmpty) {
      _timers.fillRange(0, _timers.length, 0.0);
      return;
    }
    final due = List<bool>.filled(rules.length, false);
    var any = false;
    for (var k = 0; k < rules.length; k++) {
      _timers[k] += dt;
      if (_timers[k] >= rules[k].period) {
        _timers[k] = 0.0;
        due[k] = true;
        any = true;
      }
    }
    if (!any) return;
    final batch = _queue;
    _queue = <IVec3>{};
    var visited = 0;
    for (final b in batch) {
      final id = _get(world, b);
      final kind = table.liquidKind(id);
      if (kind == VoxelBlockDef.noLiquid) continue;
      if (!due[kind] || visited >= budget) {
        _queue.add(b); // not its turn yet, or over budget: next tick
        continue;
      }
      visited += 1;
      _step(world, b, id, kind);
    }
  }

  int _get(VoxelQuery w, IVec3 b) => w.getBlockXYZ(b.x, b.y, b.z);

  int _distOf(IVec3 b, int id) => table.isLiquidSource(id) ? 0 : (_dist[b] ?? unknown);

  void _step(VoxelEditor world, IVec3 b, int id, int kind) {
    final react = contact;
    if (react != null) {
      for (final d in _six) {
        final other = table.liquidKind(_get(world, b + d));
        if (other == VoxelBlockDef.noLiquid || other == kind) continue;
        final into = react(kind, table.isLiquidSource(id), other);
        if (into != null) {
          _set(world, b, into);
          return;
        }
      }
    }
    final rule = rules[kind];
    var dist = _distOf(b, id);
    if (!table.isLiquidSource(id)) {
      var fed = unknown;
      if (table.liquidKind(_get(world, b + IVec3.up)) == kind) {
        fed = 0;
      } else {
        for (final d in _four) {
          final n = b + d;
          final nid = _get(world, n);
          if (table.liquidKind(nid) == kind) fed = math.min(fed, _distOf(n, nid) + 1);
        }
      }
      if (fed > rule.reach || fed > dist) fed = unknown;
      if (fed == unknown) {
        _dist.remove(b);
        _set(world, b, VoxelBlockTable.air);
        return;
      }
      if (fed != dist) {
        _dist[b] = fed;
        dist = fed;
        for (final d in _four) {
          if (table.liquidKind(_get(world, b + d)) == kind) _queue.add(b + d);
        }
      }
    }
    // Down first; sideways only when resting on a solid or a source. Above a
    // flowing cell the column just keeps falling: the cell that lands does the
    // spreading, so a stream is one block wide.
    final below = b + IVec3.down;
    final belowId = _get(world, below);
    if (_enters(belowId)) {
      _dist[below] = 0;
      _set(world, below, rule.flowingId);
      return;
    }
    if (!(table.isSolid(belowId) || table.isLiquidSource(belowId))) return;
    if (dist >= rule.reach) return;
    for (final d in _four) {
      final n = b + d;
      final nid = _get(world, n);
      if (_enters(nid)) {
        _dist[n] = dist + 1;
        _set(world, n, rule.flowingId);
      } else if (table.liquidKind(nid) == kind && !table.isLiquidSource(nid) && _distOf(n, nid) > dist + 1) {
        _dist[n] = dist + 1;
        _queue.add(n);
      }
    }
  }

  bool _enters(int id) => canEnter(id) && !table.isLiquid(id);

  void _set(VoxelEditor world, IVec3 b, int id) {
    if (world.setBlock(b, id)) _updates += 1;
  }
}
