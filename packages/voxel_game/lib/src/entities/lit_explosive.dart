import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart' show BlockType;
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../spec/explosive.dart';
import 'game_entity.dart';

/// An [Explosive] lit: a copy of its [block] where the block stood, flashing
/// white every [blink] seconds and falling as a body does, until [fuse] runs
/// out and it bursts. A client draws the host's as a [replica], which flashes
/// and falls the same and at its end only sounds: the host's blast breaks
/// the blocks and lands the blows. A save keeps none: a lit one is spent.
class LitExplosive extends GameEntity {
  /// [block], lit as [explosive], standing on [at] (the middle of its
  /// cell's floor), bursting in [fuse] seconds.
  LitExplosive(this.block, this.explosive, Vector3 at, {required this.fuse}) : assert(fuse > 0.0) {
    position = at.clone();
    velocity = Vector3.zero();
    halfWidth = _half;
    height = _half * 2.0;
  }

  /// What it looks like.
  final BlockType block;

  /// How it bursts.
  final Explosive explosive;

  /// Seconds it burns in all.
  final double fuse;

  /// A client's copy of the host's: it sounds at its end, nothing more.
  bool replica = false;

  /// Seconds between turning white and back.
  static const double blink = 0.4;

  static const double _half = 0.49;

  double _age = 0.0;

  /// Seconds left before it bursts.
  double get left => fuse - _age;

  /// Whether it shows white now.
  bool get white => (_age / blink) % 2.0 >= 1.0;

  Node? _box;
  MeshGeometry? _geometry;
  bool _shownWhite = false;

  static final Map<(double, double, double), MeshGeometry> _geometries = {};

  @override
  void attached(VoxelGame game) {
    setup(game.world, _half, _half * 2.0);
    if (game.headless) return;
    final geometry = _geometry = _geometries[(block.r, block.g, block.b)] ??= _cube(Vector3(block.r, block.g, block.b));
    node.add(_box = Node(mesh: Mesh(geometry, VoxelModelMesh.material())));
  }

  /// A cube a block a side, standing on its floor's middle, in [color].
  static MeshGeometry _cube(Vector3 color) {
    final voxels = <IVec3, Vector3>{};
    VoxelModel.box(voxels, IVec3.zero, const IVec3(7, 7, 7), color);
    return VoxelModelMesh.geometry(voxels, _half * 2.0 / 8.0, Vector3(4.0, 0.0, 4.0))!;
  }

  @override
  void tick(VoxelGame game, double dt) {
    _age += dt;
    if (_age >= fuse) {
      removed = true;
      if (replica) {
        game.playSound('explode', at: centre());
      } else {
        game.explode(centre(), radius: explosive.radius, damage: explosive.damage);
      }
      return;
    }
    if (game.world.isLoaded(IVec3.floor(position))) {
      applyGravity(dt);
      if (onFloor) {
        velocity.x *= 0.8;
        velocity.z *= 0.8;
      }
      move(dt);
    }
    _show();
  }

  void _show() {
    syncNode();
    final box = _box;
    if (box == null || white == _shownWhite) return;
    _shownWhite = white;
    // flutter_scene copies a primitive's material into its render item when
    // the mesh is set: a new mesh over the same geometry is what reaches it.
    box.mesh = Mesh(_geometry!, white ? VoxelModelMesh.flash() : VoxelModelMesh.material());
  }
}
