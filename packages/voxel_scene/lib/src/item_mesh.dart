import 'package:flutter_scene/scene.dart';
import 'package:voxel_engine/content.dart';

import 'voxel_model_mesh.dart';

/// The mesh of one [ItemModel], built the first time it is drawn ([of]).
/// Everything that draws the item — the hand, a body holding it, every drop
/// of it on the ground — hangs its own [node] on the one geometry and the
/// shared [VoxelModelMesh.material], so flutter_scene draws them once a pass,
/// instanced, instead of once each.
class ItemMesh {
  ItemMesh._(this.model);

  /// The mesh of [model]: the same object for every call with it.
  factory ItemMesh.of(ItemModel model) => _built[model] ??= ItemMesh._(model);

  static final Map<ItemModel, ItemMesh> _built = {};

  /// What it draws.
  final ItemModel model;

  /// The geometry, one for everything drawing [model].
  late final MeshGeometry geometry = VoxelModelMesh.geometry(model.voxels, model.scale, model.origin)!;

  /// A new node drawing the model, standing on its grip.
  Node node() => Node(mesh: Mesh(geometry, VoxelModelMesh.material()));
}
