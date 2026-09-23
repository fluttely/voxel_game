import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import 'terrain_material.dart';

/// voxel_core's chunks drawn with flutter_scene: the [ChunkMeshSink] a
/// [ChunkStreamer] hands finished meshes to. One [Node] per chunk under [root],
/// one child per non-empty surface on its material, light in the second UV set.
class VoxelChunkView implements ChunkMeshSink {
  /// A view with an empty [root] named [rootName]. Add [root] to a scene.
  VoxelChunkView({String rootName = 'World'}) : root = Node(name: rootName) {
    // The three lit surfaces share the terrain shader's light term fed by
    // [setSkyIntensity]; specular 0 turns off sky reflections (the dielectric F0
    // would add ~0.04 of the sky to every face).
    matSolid = TerrainMaterial()
      ..roughnessFactor = 1.0
      ..metallicFactor = 0.0
      ..specular = 0.0;
    matCutout = TerrainMaterial()
      ..roughnessFactor = 1.0
      ..metallicFactor = 0.0
      ..specular = 0.0
      ..doubleSided = true;
    matLiquid = TerrainMaterial()
      ..roughnessFactor = 0.15
      ..metallicFactor = 0.1
      ..alphaMode = AlphaMode.blend
      ..doubleSided = true;
    // Unlit, so a lamp's faces keep their colour at night.
    matGlow = UnlitMaterial()..vertexColorWeight = 1.0;
  }

  /// The parent of every chunk node.
  final Node root;

  /// Draws [ChunkMeshResult.solid]: rough, no specular.
  late final TerrainMaterial matSolid;

  /// Draws [ChunkMeshResult.cutout]: as [matSolid], double-sided.
  late final TerrainMaterial matCutout;

  /// Draws [ChunkMeshResult.liquid]: blended, double-sided, a little glossy.
  late final TerrainMaterial matLiquid;

  /// Draws [ChunkMeshResult.glow]: unlit vertex colour.
  late final UnlitMaterial matGlow;

  final Map<ChunkPos, Node> _nodes = {};

  /// Chunks with a node under [root].
  int get nodeCount => _nodes.length;

  /// How much of the baked skylight shows (1.0 noon, 0.35 night, 0.0 none),
  /// read by the three lit materials when they bind.
  void setSkyIntensity(double value) {
    matSolid.skyIntensity = value;
    matCutout.skyIntensity = value;
    matLiquid.skyIntensity = value;
  }

  Node? _surfaceNode(MeshSurface s, Material material) {
    if (s.isEmpty) return null;
    final geometry = MeshGeometry.fromArrays(
      positions: s.positions,
      normals: s.normals,
      colors: s.colors,
      texCoords1: s.light, // (sky / 15, block / 15)
      indices: s.indices,
      retainCpuData: false,
    );
    return Node(mesh: Mesh(geometry, material))..shadowStatic = true;
  }

  @override
  void apply(ChunkPos pos, ChunkMeshResult surface) {
    final old = _nodes[pos];
    if (old != null) root.remove(old);
    final node = Node(name: 'chunk_${pos.x}_${pos.z}')
      ..position = Vector3(pos.x * ChunkSize.sizeX.toDouble(), 0, pos.z * ChunkSize.sizeZ.toDouble());
    final solid = _surfaceNode(surface.solid, matSolid);
    final cutout = _surfaceNode(surface.cutout, matCutout);
    final liquid = _surfaceNode(surface.liquid, matLiquid);
    final glow = _surfaceNode(surface.glow, matGlow);
    if (solid != null) node.add(solid);
    if (cutout != null) node.add(cutout);
    if (glow != null) node.add(glow);
    if (liquid != null) node.add(liquid);
    root.add(node);
    _nodes[pos] = node;
  }

  @override
  void remove(ChunkPos pos) {
    final node = _nodes.remove(pos);
    if (node != null) root.remove(node);
  }
}
