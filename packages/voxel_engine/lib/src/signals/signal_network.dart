import 'package:voxel_engine/core.dart';

/// What a block does when the network around it changes: read
/// [SignalNetwork.isPowered] at [cell] and write the world.
typedef SignalReaction = void Function(SignalNetwork net, IVec3 cell, int id);

/// A button: pressed it becomes [pressed] for [seconds], then goes back.
typedef ButtonRule = ({int pressed, double seconds});

/// What each block is to a [SignalNetwork], by id. Every state is a block id
/// (a lever on and off, a lit and an unlit lamp), so a flip is a plain
/// `setBlock` and meshing, saving and networking come free.
class SignalRules {
  /// The rules of one game.
  const SignalRules({
    required this.wireOff,
    required this.wireOn,
    this.sources = const {},
    this.pressSources = const {},
    this.toggles = const {},
    this.buttons = const {},
    this.reactions = const {},
    this.maxStrength = 15,
    this.period = 0.1,
    this.networkCap = 400,
  });

  /// An unpowered wire.
  final int wireOff;

  /// A powered wire.
  final int wireOn;

  /// Blocks that power what touches them while they stand (a lever on, a
  /// button pressed, a powered block).
  final Set<int> sources;

  /// Blocks that power only while pressed (a plate with a body on it): see
  /// [SignalNetwork.setPressed].
  final Set<int> pressSources;

  /// What [SignalNetwork.use] turns a block into (a lever off to on, and back).
  final Map<int, int> toggles;

  /// What [SignalNetwork.use] presses, and for how long.
  final Map<int, ButtonRule> buttons;

  /// What reacts to power, by id: lamps, doors, pistons, TNT, powered rails.
  final Map<int, SignalReaction> reactions;

  /// The strength beside a source; a wire carries one less per link.
  final int maxStrength;

  /// Seconds between two rebuilds of dirty networks.
  final double period;

  /// The most wire cells one rebuild floods.
  final int networkCap;

  /// Whether [id] is a wire.
  bool isWire(int id) => id == wireOff || id == wireOn;

  /// Whether [id] takes part in circuits at all.
  bool isCircuit(int id) =>
      id != VoxelBlockTable.air &&
      (isWire(id) ||
          sources.contains(id) ||
          pressSources.contains(id) ||
          toggles.containsKey(id) ||
          buttons.containsKey(id) ||
          buttons.values.any((b) => b.pressed == id) ||
          reactions.containsKey(id));
}

/// Redstone-lite over a [VoxelEditor]. Sources power their six neighbours;
/// power runs along wires with a strength of [SignalRules.maxStrength] beside a
/// source, one less per link. Wires link on the same plane (four neighbours)
/// and one step up or down along a block edge — the staircase rule: the climb
/// needs no opaque block over the lower cell, the drop none in the far cell. A
/// block beside a source or a live wire is powered, and its reaction runs.
///
/// Nothing is incremental: an edit near a circuit marks its cell dirty
/// ([touch], called from every block edit), and every [SignalRules.period] the
/// wire networks the dirty cells touch are flooded (capped) and recomputed.
class SignalNetwork {
  /// A network over [world] by [rules].
  SignalNetwork(this.world, this.rules);

  /// The world written.
  final VoxelEditor world;

  /// What each block is.
  final SignalRules rules;

  static const List<IVec3> _six = [
    IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), //
  ];
  static const List<IVec3> _four = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)];

  /// Network rebuilds so far.
  int recomputes = 0;

  final Map<IVec3, int> _power = {};
  final Set<IVec3> _dirty = {};
  Set<IVec3> _pressed = {};
  final Map<IVec3, double> _buttonsDown = {};
  late double _timer = rules.period;
  bool _applying = false;

  int _get(IVec3 c) => world.getBlockXYZ(c.x, c.y, c.z);

  void _set(IVec3 c, int id) => world.setBlock(c, id);

  /// The use action on [cell]: a toggle flips, a button presses. False when
  /// the block is neither.
  bool use(IVec3 cell) {
    final id = _get(cell);
    final t = rules.toggles[id];
    if (t != null) return world.setBlock(cell, t);
    final b = rules.buttons[id];
    if (b != null) return world.setBlock(cell, b.pressed);
    return false;
  }

  /// Every block edit passes here: a circuit block appearing or going, or any
  /// edit beside a wire, marks the cell for the next rebuild.
  void touch(IVec3 cell, int old, int id) {
    if (_applying) return;
    for (final b in rules.buttons.values) {
      if (id == b.pressed) {
        _buttonsDown[cell] = b.seconds;
      } else if (old == b.pressed) {
        _buttonsDown.remove(cell);
      }
    }
    if (rules.isWire(old)) _power.remove(cell);
    if (rules.isCircuit(old) || rules.isCircuit(id)) {
      _dirty.add(cell);
      return;
    }
    for (final d in _six) {
      if (rules.isWire(_get(cell + d))) {
        _dirty.add(cell);
        return;
      }
    }
  }

  /// The pressed cells this tick (plates with a body on them); a plate that
  /// changed state wakes its network.
  void setPressed(Set<IVec3> pressed) {
    for (final c in pressed) {
      if (!_pressed.contains(c)) _dirty.add(c);
    }
    for (final c in _pressed) {
      if (!pressed.contains(c)) _dirty.add(c);
    }
    _pressed = Set.of(pressed);
  }

  /// Marks [cell] for the next rebuild (a reaction that moved a block).
  void markDirty(IVec3 cell) => _dirty.add(cell);

  /// Releases buttons whose time is up and rebuilds dirty networks when the
  /// period has passed; once a simulation step.
  void tick(double dt) {
    for (final cell in List.of(_buttonsDown.keys)) {
      final left = _buttonsDown[cell]! - dt;
      _buttonsDown[cell] = left;
      if (left <= 0.0) {
        _buttonsDown.remove(cell);
        final id = _get(cell);
        for (final e in rules.buttons.entries) {
          if (e.value.pressed == id) _set(cell, e.key);
        }
      }
    }
    _timer += dt;
    if (_dirty.isEmpty || _timer < rules.period) return;
    _timer = 0.0;
    final seeds = List.of(_dirty);
    _dirty.clear();
    _recompute(seeds);
  }

  /// The strength a wire cell carries, 0 when unpowered or not a wire.
  int strengthAt(IVec3 cell) => _power[cell] ?? 0;

  /// Cells waiting for a rebuild.
  int get pending => _dirty.length;

  bool _isSource(IVec3 c) {
    final id = _get(c);
    if (rules.sources.contains(id)) return true;
    return rules.pressSources.contains(id) && _pressed.contains(c);
  }

  bool _opaque(IVec3 c) => world.table.isOpaque(_get(c));

  List<IVec3> _links(IVec3 b) {
    final out = <IVec3>[];
    final openAbove = !_opaque(b + IVec3.up);
    for (final d in _four) {
      final n = b + d;
      final nid = _get(n);
      if (rules.isWire(nid)) {
        out.add(n);
        continue;
      }
      if (openAbove && rules.isWire(_get(n + IVec3.up))) {
        out.add(n + IVec3.up);
      } else if (!world.table.isOpaque(nid) && rules.isWire(_get(n + IVec3.down))) {
        out.add(n + IVec3.down);
      }
    }
    return out;
  }

  /// Whether a source or a live wire touches [cell] on one of its six faces.
  bool isPowered(IVec3 cell) {
    for (final d in _six) {
      final n = cell + d;
      if (_isSource(n) || _get(n) == rules.wireOn) return true;
    }
    return false;
  }

  void _recompute(List<IVec3> seeds) {
    recomputes += 1;
    final wires = <IVec3>{};
    final frontier = <IVec3>[];
    for (final s in seeds) {
      for (final c in [s, for (final d in _six) s + d]) {
        if (rules.isWire(_get(c)) && wires.add(c)) frontier.add(c);
      }
    }
    var head = 0;
    while (head < frontier.length && wires.length < rules.networkCap) {
      final c = frontier[head++];
      for (final n in _links(c)) {
        if (wires.add(n)) frontier.add(n);
      }
    }
    final strength = <IVec3, int>{};
    final queue = <IVec3>[];
    for (final c in wires) {
      for (final d in _six) {
        if (_isSource(c + d)) {
          strength[c] = rules.maxStrength;
          queue.add(c);
          break;
        }
      }
    }
    head = 0;
    while (head < queue.length) {
      final c = queue[head++];
      final s = strength[c]!;
      if (s <= 1) continue;
      for (final n in _links(c)) {
        if (wires.contains(n) && (strength[n] ?? 0) < s - 1) {
          strength[n] = s - 1;
          queue.add(n);
        }
      }
    }
    _applying = true;
    for (final c in wires) {
      final s = strength[c] ?? 0;
      if (s > 0) {
        _power[c] = s;
      } else {
        _power.remove(c);
      }
      final want = s > 0 ? rules.wireOn : rules.wireOff;
      if (_get(c) != want) _set(c, want);
    }
    final candidates = <IVec3>{};
    for (final c in wires) {
      for (final d in _six) {
        candidates.add(c + d);
      }
    }
    for (final s in seeds) {
      candidates.add(s);
      for (final d in _six) {
        candidates.add(s + d);
      }
    }
    for (final c in candidates) {
      final id = _get(c);
      if (id == VoxelBlockTable.air) continue;
      rules.reactions[id]?.call(this, c, id);
    }
    _applying = false;
  }
}

/// Stock [SignalReaction]s.
abstract final class SignalReactions {
  /// A lamp: [off] when unpowered, [on] when powered. Register it for both ids.
  static SignalReaction swap(int off, int on) => (net, cell, id) {
    final want = net.isPowered(cell) ? on : off;
    if (id != want) net.world.setBlock(cell, want);
  };

  /// Calls [then] while powered (TNT lit by a wire).
  static SignalReaction trigger(void Function(IVec3 cell) then) => (net, cell, id) {
    if (net.isPowered(cell)) then(cell);
  };

  /// A two-high door: [closedToOpen] pairs its states; both halves open
  /// together when either is powered. [onSwing] after the lower half turns.
  /// Register it for every closed and open id.
  static SignalReaction door(Map<int, int> closedToOpen, {void Function(IVec3 lower)? onSwing}) {
    final openToClosed = {for (final e in closedToOpen.entries) e.value: e.key};
    bool isDoor(int id) => closedToOpen.containsKey(id) || openToClosed.containsKey(id);
    return (net, cell, id) {
      final w = net.world;
      int at(IVec3 c) => w.getBlockXYZ(c.x, c.y, c.z);
      var lower = cell;
      if (isDoor(at(cell + IVec3.down))) lower = cell + IVec3.down;
      final upper = lower + IVec3.up;
      final powered = net.isPowered(lower) || net.isPowered(upper);
      final closed = openToClosed[id] ?? id;
      final want = powered ? closedToOpen[closed]! : closed;
      if (at(lower) != want) {
        w.setBlock(lower, want);
        onSwing?.call(lower);
      }
      if (isDoor(at(upper)) && at(upper) != want) w.setBlock(upper, want);
    };
  }

  /// A piston: [retractedToExtended] pairs its states, [facing] is the way a
  /// state pushes. Powered, the block in front moves one cell on when the cell
  /// past it gives way ([givesWay]) and the block is [pushable]; a blocked
  /// piston stays retracted. Unpowered, the head pulls back (nothing is
  /// pulled). Register it for every state.
  static SignalReaction piston(
    Map<int, int> retractedToExtended, {
    required IVec3 Function(int id) facing,
    required bool Function(int id) pushable,
    required bool Function(int id) givesWay,
    void Function(IVec3 cell)? onExtend,
  }) {
    final extendedToRetracted = {for (final e in retractedToExtended.entries) e.value: e.key};
    return (net, c, id) {
      final w = net.world;
      int at(IVec3 p) => w.getBlockXYZ(p.x, p.y, p.z);
      final extended = extendedToRetracted.containsKey(id);
      final powered = net.isPowered(c);
      if (extended == powered) return;
      final base = extended ? extendedToRetracted[id]! : id;
      if (!powered) {
        w.setBlock(c, base);
        return;
      }
      final dir = facing(id);
      final front = c + dir;
      final fid = at(front);
      if (fid != VoxelBlockTable.air) {
        final beyond = front + dir;
        if (!pushable(fid) || !givesWay(at(beyond))) return;
        w.setBlock(beyond, fid);
        w.setBlock(front, VoxelBlockTable.air);
        net
          ..markDirty(front)
          ..markDirty(beyond);
      }
      w.setBlock(c, retractedToExtended[base]!);
      onExtend?.call(c);
    };
  }

  /// A run of powered rails (or any line of blocks): [offToOn] pairs the
  /// states. The run is the blocks joined on the four sides from the cell
  /// (capped at 64); every one within [reach] steps along it of a powered one
  /// is on. Register it for every state.
  static SignalReaction poweredRun(Map<int, int> offToOn, {int reach = 8}) {
    final onToOff = {for (final e in offToOn.entries) e.value: e.key};
    bool inRun(int id) => offToOn.containsKey(id) || onToOff.containsKey(id);
    const four = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)];
    return (net, c, id) {
      final w = net.world;
      int at(IVec3 p) => w.getBlockXYZ(p.x, p.y, p.z);
      final run = <IVec3>[c];
      final seen = <IVec3>{c};
      var head = 0;
      while (head < run.length && run.length < 64) {
        final cur = run[head++];
        for (final d in four) {
          final n = cur + d;
          if (seen.contains(n)) continue;
          final nid = at(n);
          if (nid != VoxelBlockTable.air && inRun(nid)) {
            seen.add(n);
            run.add(n);
          }
        }
      }
      final dist = <IVec3, int>{};
      final queue = <IVec3>[];
      for (final cell in run) {
        if (net.isPowered(cell)) {
          dist[cell] = 0;
          queue.add(cell);
        }
      }
      head = 0;
      while (head < queue.length) {
        final cur = queue[head++];
        for (final d in four) {
          final n = cur + d;
          if (seen.contains(n) && !dist.containsKey(n)) {
            dist[n] = dist[cur]! + 1;
            queue.add(n);
          }
        }
      }
      for (final cell in run) {
        final cur = at(cell);
        final off = onToOff[cur] ?? cur;
        final want = (dist[cell] ?? 99) <= reach ? offToOn[off]! : off;
        if (cur != want) w.setBlock(cell, want);
      }
    };
  }
}
