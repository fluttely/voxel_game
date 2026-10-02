import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

/// voxel_core's [VoxelModel]s as flutter_scene meshes: creatures, held items,
/// drops. The faces wind like the chunk meshes, so they are seen through a
/// [MirroredCamera].
abstract final class VoxelModelMesh {
  static PhysicallyBasedMaterial? _material;

  /// The material every model shares: vertex colours, rough, not metallic.
  static PhysicallyBasedMaterial material() => _material ??= PhysicallyBasedMaterial()
    ..roughnessFactor = 0.9
    ..metallicFactor = 0.0;

  static UnlitMaterial? _flash;
  static final Map<(double, double, double, double), PhysicallyBasedMaterial> _tinted = {};

  /// The white a model turns for a moment when it is hit: unlit, its colours
  /// left out. One for every model, so the flashing ones still batch.
  static UnlitMaterial flash() => _flash ??= UnlitMaterial()
    ..baseColorFactor = Vector4(1, 1, 1, 1)
    ..vertexColorWeight = 0.0;

  /// [material] tinted by [tint], RGBA multiplied into the voxel colours:
  /// see-through (the translucent pass, no shadow) when its alpha is under 1.
  /// One material a tint, shared by every model drawn in it, so they still
  /// batch: ask for a handful of tints (a ghost's, a burn's, a fade's steps),
  /// not a new one every frame. White and whole is [material] itself.
  static PhysicallyBasedMaterial tinted(Vector4 tint) {
    final key = (tint.r, tint.g, tint.b, tint.a);
    if (key == (1.0, 1.0, 1.0, 1.0)) return material();
    if (!(tint.a >= 0.0 && tint.a <= 1.0)) throw ArgumentError.value(tint.a, 'tint', 'alpha is 0..1');
    return _tinted[key] ??= PhysicallyBasedMaterial()
      ..roughnessFactor = 0.9
      ..metallicFactor = 0.0
      ..baseColorFactor = tint.clone()
      ..alphaMode = tint.a < 1.0 ? AlphaMode.blend : AlphaMode.opaque;
  }

  /// The mesh geometry of [voxels] (see [VoxelModel.arrays]), or null for an
  /// empty model.
  static MeshGeometry? geometry(Map<IVec3, Vector3> voxels, double scale, [Vector3? origin]) {
    final a = VoxelModel.arrays(voxels, scale, origin);
    if (a == null) return null;
    return MeshGeometry.fromArrays(positions: a.positions, normals: a.normals, colors: a.colors, indices: a.indices);
  }

  /// A node drawing [voxels] with the shared [material]; an empty model gives
  /// an empty node.
  static Node node(Map<IVec3, Vector3> voxels, double scale, [Vector3? origin]) {
    final g = geometry(voxels, scale, origin);
    final node = Node();
    if (g != null) node.mesh = Mesh(g, material());
    return node;
  }
}

/// flutter_scene 0.23 copies a primitive's material into its render item when
/// the mesh is assigned to the node, so writing `primitive.material` alone
/// never reaches the screen. Re-assigning the same primitives as a new [Mesh]
/// keeps the render items (same geometry) and refreshes their materials. Call
/// after swapping the materials of [n]'s mesh.
void refreshMeshMaterials(Node n) {
  final mesh = n.mesh;
  if (mesh == null) return;
  n.mesh = Mesh.primitives(primitives: mesh.primitives);
}
