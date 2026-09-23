import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../core/blocks.dart';
import 'package:voxel_engine/core.dart';
import '../game/inventory.dart';
import '../game/rails.dart';
import '../world/voxel_world.dart';
import 'package:voxel_scene/voxel_scene.dart';

/// Stage 28: a cart that lives on the rail graph rather than in free space
/// (Godot `src/entities/minecart.gd`). Its state is the rail cell it is in, the
/// two ends of that rail it entered and leaves by, [t] (0 at the entry end, 1
/// at the exit end) and a speed along the line. Each simulation tick the speed
/// takes the slope (4 m/s² downhill, the same against it uphill), flat friction
/// (0.4 m/s²), a powered rail (+6 m/s² on, a hard brake off) and the rider's
/// push (±2 m/s²), then [t] advances and a crossing picks the next rail from the
/// orientation; a line that ends stops the cart. Like a boat (stage 25) the
/// host owns every cart: a [replica] only lerps to streamed poses.
class Minecart {
  static const double maxSpeed = 8.0;
  static const double railTop = 0.125;
  static const double slopeAccel = 4.0;
  static const double friction = 0.4;
  static const double poweredAccel = 6.0;
  static const double poweredBrake = 12.0;
  static const double pushAccel = 2.0;
  static final Vector3 seatOffset = Vector3(0, 0.3, 0);

  late VoxelWorld world;
  final Node node = Node();
  final Node _model = Node();
  Vector3 position = Vector3.zero();
  bool removed = false;

  /// "minecart" or "chest_minecart".
  String kind = 'minecart';
  IVec3 cell = IVec3.zero;
  double t = 0.5;
  double speed = 0.0;

  /// The rider's W/S, -1..1 along the heading.
  double push = 0.0;

  /// The local player or, on the host, a peer's puppet.
  Object? rider;

  /// The chest cart's slots.
  Inventory? cargo;
  bool replica = false;
  int netId = 0;
  Vector3? lastSent;
  double lastSentYaw = double.infinity;
  double yaw = 0.0;

  /// The line ended under the cart (or it never moved).
  bool stopped = true;
  IVec3 _from = const IVec3(-1, 0, 0); // the end of `cell`'s rail the cart came in by
  IVec3 _to = const IVec3(1, 0, 0); // the end it leaves by
  Vector3? _netTarget;
  double _netYaw = 0.0;

  /// [model] false builds no mesh (unit tests run without a GPU).
  void setupCart(VoxelWorld w, IVec3 at, String cartKind, {bool model = true}) {
    world = w;
    kind = cartKind;
    if (kind == 'chest_minecart') cargo = Inventory();
    if (model) {
      final v = <IVec3, Vector3>{};
      final iron = Vector3(0.55, 0.55, 0.58);
      final dark = Vector3(0.32, 0.32, 0.35);
      final wood = Vector3(0.55, 0.38, 0.20);
      VoxelModel.box(v, const IVec3(-4, 0, -3), const IVec3(4, 0, 3), dark);
      VoxelModel.box(v, const IVec3(-5, 1, -4), const IVec3(-4, 4, 4), iron);
      VoxelModel.box(v, const IVec3(4, 1, -4), const IVec3(5, 4, 4), iron);
      VoxelModel.box(v, const IVec3(-4, 1, -4), const IVec3(4, 4, -3), iron);
      VoxelModel.box(v, const IVec3(-4, 1, 3), const IVec3(4, 4, 4), iron);
      if (kind == 'chest_minecart') VoxelModel.box(v, const IVec3(-3, 1, -2), const IVec3(3, 4, 2), wood);
      for (final wx in const [-3, 3]) {
        for (final wz in const [-3, 2]) {
          VoxelModel.box(v, IVec3(wx - 1, -1, wz), IVec3(wx + 1, 0, wz + 1), dark);
        }
      }
      _model.add(VoxelModelMesh.node(v, 0.1, Vector3(0.5, 0.1, 0.5)));
      node.add(_model);
    }
    placeOn(at);
  }

  /// Stand the cart in the middle of the rail at [at], heading along its first end.
  void placeOn(IVec3 at) {
    cell = at;
    final id = world.getBlock(cell);
    if (id != Blocks.air && Blocks.isRail(id)) {
      final ends = Rails.connections(id);
      _from = ends[1];
      _to = ends[0];
    }
    t = 0.5;
    speed = 0.0;
    stopped = true;
    position = _point(t);
    _face();
  }

  /// Point the cart along [d] (a horizontal unit step) when the rail under it
  /// has that end.
  void head(IVec3 d) {
    final id = world.getBlock(cell);
    if (id == Blocks.air || !Blocks.isRail(id)) return;
    for (final e in Rails.connections(id)) {
      if (IVec3(e.x, 0, e.z) == d) {
        if (e != _to) _reverse();
        return;
      }
    }
  }

  IVec3 heading() => IVec3(_to.x, 0, _to.z);

  Vector3 seat() => position + seatOffset;

  /// Whether a ray from [origin] along [dir] meets the cart's box (grown by
  /// 0.15) within [reach] metres.
  bool rayHits(Vector3 origin, Vector3 dir, double reach) {
    const g = 0.15;
    final mn = position - Vector3(0.5 + g, g, 0.5 + g);
    final mx = position + Vector3(0.5 + g, 0.7 + g, 0.5 + g);
    var near = double.negativeInfinity;
    var far = double.infinity;
    for (var axis = 0; axis < 3; axis++) {
      final d = dir[axis];
      if (d == 0.0) {
        if (origin[axis] < mn[axis] || origin[axis] > mx[axis]) return false;
        continue;
      }
      final a = (mn[axis] - origin[axis]) / d;
      final b = (mx[axis] - origin[axis]) / d;
      near = math.max(near, math.min(a, b));
      far = math.min(far, math.max(a, b));
    }
    if (far < near || far < 0.0) return false;
    final hitT = near > 0.0 ? near : 0.0;
    return hitT * dir.length <= reach;
  }

  void _reverse() {
    final f = _from;
    _from = _to;
    _to = f;
    t = 1.0 - t;
  }

  Vector3 _endPoint(IVec3 end) =>
      Vector3(cell.x + 0.5 + end.x * 0.5, cell.y + railTop + end.y, cell.z + 0.5 + end.z * 0.5);

  static Vector3 _lerp(Vector3 a, Vector3 b, double k) => a + (b - a) * k;

  /// Where the cart sits at [u] in 0..1 along the current rail. A curve bends
  /// through the centre as two half segments; a slope is the straight line
  /// between its two end heights.
  Vector3 _point(double u) {
    final a = _endPoint(_from);
    final b = _endPoint(_to);
    if ((_from.x != 0 && _to.z != 0) || (_from.z != 0 && _to.x != 0)) {
      final c = Vector3(cell.x + 0.5, cell.y + railTop, cell.z + 0.5);
      if (u < 0.5) return _lerp(a, c, u * 2.0);
      return _lerp(c, b, (u - 0.5) * 2.0);
    }
    return _lerp(a, b, u);
  }

  void _face() {
    final h = _point(math.min(t + 0.05, 1.0)) - _point(math.max(t - 0.05, 0.0));
    if (h.length2 > 0.0001) yaw = math.atan2(-h.x, -h.z);
    _syncModel();
  }

  void _syncModel() {
    node.position = position.clone();
    _model.rotation = eulerYXZ(0, yaw, 0);
  }

  void update(double dt) {
    if (replica) {
      final target = _netTarget;
      if (target != null) {
        final k = (dt * 12.0).clamp(0.0, 1.0);
        position = _lerp(position, target, k);
        yaw = lerpAngle(yaw, _netYaw, k);
      }
      _syncModel();
      return;
    }
    if (!world.isLoaded(cell)) return; // a restored cart waits for its chunk
    final id = world.getBlock(cell);
    if (id == Blocks.air || !Blocks.isRail(id)) {
      // The rail under the cart went: stay where it is.
      speed = 0.0;
      stopped = true;
      return;
    }
    var accel = 0.0;
    if (_to.y == 1) {
      accel -= slopeAccel;
    } else if (_from.y == 1) {
      accel += slopeAccel;
    }
    if (Blocks.isPoweredRail(id)) {
      if (Blocks.idOf(id).endsWith('_on')) {
        accel += poweredAccel;
      } else {
        accel -= speed > 0.0 ? poweredBrake : 0.0;
      }
    }
    accel += push * pushAccel;
    var v = math.max(speed - friction * dt, 0.0) + accel * dt;
    if (v < 0.0) {
      if (_to.y == 1 || push < 0.0) {
        _reverse();
        v = -v;
      } else {
        v = 0.0;
      }
    }
    speed = math.min(v, maxSpeed);
    stopped = speed <= 0.0;
    if (stopped) return;
    t += speed * dt;
    var hops = 0;
    while (t >= 1.0 && hops < 4) {
      hops += 1;
      final next = Rails.nextCell(world, cell, _to);
      final into = next != cell ? Rails.endToward(world, next, cell) : IVec3.zero;
      if (next == cell || into == IVec3.zero) {
        t = 1.0;
        speed = 0.0;
        stopped = true;
        _reverse();
        break;
      }
      cell = next;
      _from = into;
      var other = _from;
      for (final e in Rails.connections(world.getBlock(cell))) {
        if (e != _from) other = e;
      }
      _to = other;
      t -= 1.0;
    }
    position = _point(t.clamp(0.0, 1.0));
    _face();
  }

  /// Replica: the host's latest pose; a jump beyond 8 m snaps, the rest is lerped.
  void setNetPose(Vector3 pos, double headingYaw) {
    if (_netTarget == null || (position - pos).length > 8.0) {
      position = pos.clone();
      yaw = headingYaw;
    }
    _netTarget = pos.clone();
    _netYaw = headingYaw;
  }

  static List<int> _iv(IVec3 v) => [v.x, v.y, v.z];

  static IVec3 _vi(Object? o, IVec3 fallback) {
    if (o is! List) return fallback;
    return IVec3((o[0] as num).toInt(), (o[1] as num).toInt(), (o[2] as num).toInt());
  }

  /// What the save keeps of a cart (Godot's `carts` rows).
  Map<String, Object> toJson() => {
        'kind': kind,
        'cell': _iv(cell),
        't': t,
        'speed': speed,
        'from': _iv(_from),
        'to': _iv(_to),
        if (cargo != null) 'cargo': cargo!.toJson(),
      };

  void fromJson(Map<String, dynamic> d) {
    cell = _vi(d['cell'], cell);
    _from = _vi(d['from'], _from);
    _to = _vi(d['to'], _to);
    t = (d['t'] as num?)?.toDouble() ?? 0.5;
    speed = (d['speed'] as num?)?.toDouble() ?? 0.0;
    stopped = speed <= 0.0;
    final c = cargo;
    if (c != null && d['cargo'] is List) c.fromJson(d['cargo'] as List<dynamic>);
    position = _point(t.clamp(0.0, 1.0));
    _face();
  }
}
