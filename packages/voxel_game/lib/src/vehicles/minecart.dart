import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/signals.dart' show RailGraph;

import '../core/voxel_game.dart';
import 'rideable.dart';
import 'vehicle.dart';
import 'vehicle_spec.dart';

/// A minecart of a [CartSpec]: it lives on the rails (`VoxelGame.rails`)
/// rather than in free space. Its state is the rail [cell] it is on, the end
/// of that rail it came in by and the one it leaves by ([heading]), how far
/// along it is between them ([along], 0 to 1) and its [speed] along the line.
///
/// Each step its speed takes the slope, the friction, a powered rail's push
/// or brake and its rider's push (`CartSpec`); then it moves along, and past
/// the end it leaves by it rolls onto the rail there that joins back (a
/// slope a cell down too), or stops at the end of the line, turned to roll
/// back. A cart slowed below rest on a climb, or pushed back, turns and rolls
/// the other way. With no rail under it, it stays where it is; while its
/// chunk is not loaded, it waits. A rail turned under it (a neighbour laid)
/// keeps it heading the nearest way the new rail goes.
///
/// Its rider pushes it by the move along the ground (`RideInput.wish`)
/// along its heading; one with no rider rolls by the rest.
class Minecart extends Vehicle {
  /// A minecart of [spec] at [at]: on the rail there, its feet [railTop] over
  /// its cell's floor, heading for the end nearest [facing]; where no rail is
  /// (or none is loaded yet), it stays at [at].
  Minecart(this.spec, super.at, {super.facing});

  @override
  final CartSpec spec;

  /// Metres over its rail's cell floor its feet ride: the top of the bars.
  static const double railTop = 0.125;

  /// The rail cell it is on.
  IVec3 get cell => _cell;
  late IVec3 _cell;

  /// The ends of [cell]'s rail it came in by and leaves by, steps from it; a
  /// slope's high end carries y = 1.
  IVec3 _from = RailGraph.w, _to = RailGraph.e;

  /// How far it is along its rail: 0 at the end it came in by, 1 at the end
  /// it leaves by.
  double get along => _t;
  double _t = 0.5;

  /// Its speed along the line, metres a second: never below 0, as it goes
  /// the way it heads.
  double get speed => _speed;
  double _speed = 0.0;

  /// The way it heads along the ground: the end of its rail it leaves by, a
  /// flat unit step.
  IVec3 get heading => IVec3(_to.x, 0, _to.z);

  @override
  void attached(VoxelGame game) {
    super.attached(game);
    _cell = IVec3.floor(position);
    final id = game.world.getBlock(_cell);
    if (!game.rails.isRail(id)) return;
    final dir = Vector3(-math.sin(facing), 0, -math.cos(facing));
    final ends = game.rails.graph.connections(id);
    final first = dir.x * ends[0].x + dir.z * ends[0].z >= dir.x * ends[1].x + dir.z * ends[1].z;
    _to = first ? ends[0] : ends[1];
    _from = first ? ends[1] : ends[0];
    _t = 0.5;
    _place();
  }

  @override
  void alone(VoxelGame game, double dt) => _roll(dt, 0.0);

  @override
  void carry(double dt, RideInput input) {
    final h = heading;
    _roll(dt, (input.wish.x * h.x + input.wish.z * h.z).clamp(-1.0, 1.0));
  }

  void _roll(double dt, double push) {
    final world = game.world;
    velocity.setZero();
    if (!world.isLoaded(_cell)) return;
    final rails = game.rails;
    final id = world.getBlock(_cell);
    if (!rails.isRail(id)) {
      _speed = 0.0;
      return;
    }
    _fit(rails.graph.connections(id));
    final before = position.clone();
    var accel = 0.0;
    if (_to.y == 1) {
      accel -= spec.slope;
    } else if (_from.y == 1) {
      accel += spec.slope;
    }
    if (rails.powers(id)) {
      accel += spec.powered;
    } else if (rails.brakes(id) && _speed > 0.0) {
      accel -= spec.brake;
    }
    accel += push * spec.push;
    var v = math.max(_speed - spec.friction * dt, 0.0) + accel * dt;
    if (v < 0.0) {
      if (_to.y == 1 || push < 0.0) {
        _reverse();
        v = -v;
      } else {
        v = 0.0;
      }
    }
    _speed = math.min(v, spec.maxSpeed);
    if (_speed > 0.0) _advance(dt);
    _place();
    velocity.setFrom((position - before) / dt);
  }

  /// Moves [speed] × [dt] along, onto the next rails while it passes their
  /// ends (four at most a step), or to the end of the line.
  void _advance(double dt) {
    final world = game.world, graph = game.rails.graph;
    _t += _speed * dt;
    var hops = 0;
    while (_t >= 1.0 && hops < 4) {
      hops += 1;
      final next = graph.nextCell(world, _cell, _to);
      final into = next != _cell ? graph.endToward(world, next, _cell) : IVec3.zero;
      if (into == IVec3.zero) {
        // The line ends: it stops there, turned to roll back.
        _t = 1.0;
        _speed = 0.0;
        _reverse();
        return;
      }
      _cell = next;
      final ends = graph.connections(world.getBlock(next));
      _from = into;
      _to = ends[0] == into ? ends[1] : ends[0];
      _t -= 1.0;
    }
  }

  /// Keeps the cart on the rail under it when that rail is no longer the one
  /// it was on ([ends] are not its own): it heads for the end nearest the way
  /// it was heading.
  void _fit(List<IVec3> ends) {
    if ((ends[0] == _from && ends[1] == _to) || (ends[0] == _to && ends[1] == _from)) return;
    final h = heading;
    final first = h.x * ends[0].x + h.z * ends[0].z >= h.x * ends[1].x + h.z * ends[1].z;
    _to = first ? ends[0] : ends[1];
    _from = first ? ends[1] : ends[0];
  }

  void _reverse() {
    final f = _from;
    _from = _to;
    _to = f;
    _t = 1.0 - _t;
  }

  Vector3 _endPoint(IVec3 end) =>
      Vector3(_cell.x + 0.5 + end.x * 0.5, _cell.y + railTop + end.y, _cell.z + 0.5 + end.z * 0.5);

  /// Where it is at [u], 0 to 1, along its rail: a curve bends through the
  /// cell's middle as two halves, a slope is the straight line between its
  /// ends' heights.
  Vector3 _point(double u) {
    final a = _endPoint(_from), b = _endPoint(_to);
    if ((_from.x != 0 && _to.z != 0) || (_from.z != 0 && _to.x != 0)) {
      final c = Vector3(_cell.x + 0.5, _cell.y + railTop, _cell.z + 0.5);
      return u < 0.5 ? a + (c - a) * (u * 2.0) : c + (b - c) * ((u - 0.5) * 2.0);
    }
    return a + (b - a) * u;
  }

  /// Puts it where [along] is on its rail, pointing the way the line runs.
  void _place() {
    position = _point(_t.clamp(0.0, 1.0));
    final h = _point(math.min(_t + 0.05, 1.0)) - _point(math.max(_t - 0.05, 0.0));
    if (h.x * h.x + h.z * h.z > 1e-6) facing = math.atan2(-h.x, -h.z);
    syncNode(yaw: facing);
  }

  /// Its row in the save, and where it is on the rails: the cell, the two
  /// ends, how far along and how fast.
  @override
  Map<String, Object?> get row => {
    ...super.row,
    'rail': {
      'cell': [_cell.x, _cell.y, _cell.z],
      'from': [_from.x, _from.y, _from.z],
      'to': [_to.x, _to.y, _to.z],
      't': _t,
      'speed': _speed,
    },
  };

  /// Takes back where it was on the rails ([row]'s `rail`, which it must
  /// have).
  @override
  void restoreRow(Map<String, Object?> row) {
    final r = row['rail']! as Map<String, Object?>;
    IVec3 v(String key) {
      final l = [for (final e in r[key]! as List<Object?>) (e! as num).toInt()];
      return IVec3(l[0], l[1], l[2]);
    }

    _cell = v('cell');
    _from = v('from');
    _to = v('to');
    _t = (r['t']! as num).toDouble();
    _speed = (r['speed']! as num).toDouble();
    _place();
  }
}
