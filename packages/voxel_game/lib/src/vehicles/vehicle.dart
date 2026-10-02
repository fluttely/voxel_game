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
/// a swing (`breakApart`). Each kind moves its own way, alone ([tick]) and
/// under its rider ([carry]); this is what they share: the seat, the way it
/// points, its look, and its row in the save ([row]).
///
/// The host owns the vehicles: a client neither puts one down nor gets on
/// (VA16).
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

  /// Whether [rider] may get on: nobody rides it, it is in the world, and this
  /// game owns it (no client gets on: the host owns the vehicles, VA16).
  @override
  bool takes(Target rider) => this.rider == null && !removed && _game.authority;

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
  /// [drop] (not for a breaker in creative). Throws while it is ridden, and
  /// for one broken already.
  void breakApart({required bool drop}) {
    if (rider != null) throw StateError('the ${name.toLowerCase()} is ridden: its rider gets off first');
    if (removed) throw StateError('the ${name.toLowerCase()} is broken already');
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
