import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../entities/target.dart';
import 'rideable.dart';
import 'vehicle_spec.dart';

/// A vehicle in the world, of its [spec]: put down with its item in hand
/// (`VoxelGame.placeVehicle`), ridden by a use, broken back into its item by
/// a swing (`breakApart`). Each kind moves its own way, alone ([alone]) and
/// under its rider ([carry]); this is what they share: the seat, the way it
/// points, its look, and its row in the save ([row]).
///
/// In a networked game the host owns the vehicles where it is: a client
/// draws them as [replica]s, and asks the host to put one down, get on,
/// get off and break one (`GameSession`). Whoever rides one moves it: the
/// other sides' copies follow the [row]s it sends ([followRow]), and the
/// side that moves it next starts where they last put it ([takeOver]).
abstract class Vehicle extends GameEntity implements Rideable {
  /// A vehicle at [at], pointing [facing].
  Vehicle(Vector3 at, {this.facing = 0.0}) {
    position = at.clone();
    halfWidth = spec.halfWidth;
    height = spec.height;
  }

  /// What it is.
  VehicleSpec get spec;

  @override
  double facing;

  @override
  Target? rider;

  @override
  String get name => spec.name;

  @override
  bool get gone => removed;

  /// The game it is in; set as the game adds it.
  VoxelGame get game => _game;
  late VoxelGame _game;

  /// Its look, which the node turns by [facing]; null headless. A kind may
  /// rock it (a boat's roll and bob): the body does not move with it.
  Node? get model => _model;
  Node? _model;

  @override
  Vector3 seat() => position + Vector3(0, spec.seat, 0);

  /// Whether [rider] may get on: nobody rides it and it is in the world. A
  /// client's player gets on a replica when the host says so
  /// (`GameSession.boardVehicle`).
  @override
  bool takes(Target rider) => this.rider == null && !removed;

  /// Its number in a networked game (the host's), 0 for one no host has
  /// numbered.
  int netId = 0;

  /// A client's copy of the host's vehicle: it moves only while the
  /// client's player rides it, and otherwise follows the host's word
  /// ([followRow]).
  bool replica = false;

  Vector3? _netTo;
  Map<String, Object?>? _netRow;

  /// Whether the other side moves it: the one its rider is on (the host's
  /// copy of a vehicle a client rides), or the host for a replica nobody
  /// here rides.
  bool get _followed => rider == null ? replica : !identical(rider, _game.player);

  /// The other side's word on it, a [row] as it sent it: drawn going there
  /// while that side moves it. Ignored while this side's player rides it:
  /// this side's copy is the live one.
  void followRow(Map<String, Object?> row) {
    if (identical(rider, _game.player)) return;
    _netTo = _vec(row['pos']);
    _netRow = row;
    facing = (row['yaw']! as num).toDouble();
  }

  /// This side moves it from now (its rider got off on the other side, or
  /// this side's player gets on a replica): it stands where the other side
  /// last put it ([followRow]), and takes back the state of its kind there
  /// ([restoreRow]).
  void takeOver() {
    final row = _netRow;
    if (row == null) return;
    position = _vec(row['pos']);
    facing = (row['yaw']! as num).toDouble();
    restoreRow(row);
    syncNode(yaw: facing);
  }

  static Vector3 _vec(Object? o) {
    final l = [for (final e in o! as List<Object?>) (e! as num).toDouble()];
    return Vector3(l[0], l[1], l[2]);
  }

  /// One step: carried by this side's rider (it moved it, [carry]), drawn
  /// going where the other side put it, or moved by its kind alone
  /// ([alone]).
  @override
  void tick(VoxelGame game, double dt) {
    if (identical(rider, game.player)) {
      // When its rider gets off, it stays here until the other side's word.
      _netTo = position.clone();
      return;
    }
    if (_followed) {
      final to = _netTo ?? position;
      final before = position.clone();
      position = position + (to - position) * math.min(1.0, dt * 12.0);
      velocity = (position - before) / math.max(dt, 1e-6);
      syncNode(yaw: facing);
      return;
    }
    alone(game, dt);
  }

  /// One step with nobody moving it: its kind's own way.
  void alone(VoxelGame game, double dt);

  @override
  void attached(VoxelGame game) {
    _game = game;
    setup(game.world, spec.halfWidth, spec.height);
    syncNode(yaw: facing);
    if (game.headless) return;
    final m = Node();
    final g = _geometry(spec);
    if (g != null) m.mesh = Mesh(g, VoxelModelMesh.material());
    node.add(m);
    _model = m;
  }

  /// Breaks it apart: gone from the world, its item dropped where it was when
  /// [drop] (not for a breaker in creative). Throws while it is ridden, for
  /// one broken already, and for a replica (the host breaks it,
  /// `GameSession.breakVehicle`).
  void breakApart({required bool drop}) {
    if (rider != null) throw StateError('the ${name.toLowerCase()} is ridden: its rider gets off first');
    if (removed) throw StateError('the ${name.toLowerCase()} is broken already');
    if (replica) throw StateError('the ${name.toLowerCase()} is the host\'s to break');
    removed = true;
    game.playSound('break_${spec.sound}', at: centre(), volumeDb: -6.0);
    if (drop) game.dropItem(spec.item, 1, position + Vector3(0, 0.5, 0));
  }

  /// What the save keeps of it: its item, where it is and the way it points.
  /// Its rider is not kept: a load stands the player where saved.
  Map<String, Object?> get row => {
    'item': spec.item,
    'pos': [position.x, position.y, position.z],
    'yaw': facing,
  };

  /// Takes back what its [row] keeps beyond its item, where it is and the way
  /// it points (`VoxelGame.restoreVehicles` puts it down by those first):
  /// nothing, for a kind that keeps no more.
  void restoreRow(Map<String, Object?> row) {}

  /// One geometry a spec, every vehicle of it hanging a node on it, so they
  /// batch (as the drops and the shots do).
  static MeshGeometry? _geometry(VehicleSpec spec) => _geometries.putIfAbsent(spec, () {
    final voxels = <IVec3, Vector3>{};
    for (final (from, to, color) in spec.model) {
      final c = Vector3(((color >> 16) & 0xFF) / 255.0, ((color >> 8) & 0xFF) / 255.0, (color & 0xFF) / 255.0);
      VoxelModel.box(voxels, from, to, c);
    }
    return VoxelModelMesh.geometry(voxels, spec.voxel, Vector3(0.5, 0, 0.5));
  });

  static final Map<VehicleSpec, MeshGeometry?> _geometries = {};
}
