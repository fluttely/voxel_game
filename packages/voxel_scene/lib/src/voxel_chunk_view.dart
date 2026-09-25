import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import 'merged_surface.dart';
import 'terrain_material.dart';

/// voxel_core's chunks drawn with flutter_scene: the [ChunkMeshSink] a
/// [ChunkStreamer] hands finished meshes to. Chunks are drawn in regions of
/// [regionChunks] × [regionChunks]: one [Node] per region under [root], one
/// child per non-empty surface on its material, light in the second UV set.
///
/// A region is one draw per surface where a chunk was one each, because
/// flutter_scene batches only draws of the identical geometry. The price is
/// that a chunk's mesh or removal rebuilds its region's geometry from the
/// surfaces of its chunks, which the view keeps.
class VoxelChunkView implements ChunkMeshSink {
  /// A view with an empty [root] named [rootName]. Add [root] to a scene.
  VoxelChunkView({String rootName = 'World', this.regionChunks = 2})
    : assert(regionChunks >= 1, 'a region holds at least one chunk'),
      root = Node(name: rootName) {
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

  /// Chunks along each side of a region.
  final int regionChunks;

  /// Each meshed chunk's four surfaces: solid, cutout, glow, liquid.
  final Map<ChunkPos, List<MeshSurface>> _chunks = {};

  /// Each region's node under [root], keyed by the region's position.
  final Map<ChunkPos, Node> _regions = {};

  /// Chunks with a mesh in the view.
  int get chunkCount => _chunks.length;

  /// Regions with a node under [root].
  int get regionCount => _regions.length;

  /// How much of the baked skylight shows (1.0 noon, 0.35 night, 0.0 none),
  /// read by the three lit materials when they bind.
  void setSkyIntensity(double value) {
    matSolid.skyIntensity = value;
    matCutout.skyIntensity = value;
    matLiquid.skyIntensity = value;
  }

  /// The region [pos] falls in, by floor division.
  ChunkPos regionOf(ChunkPos pos) =>
      (x: (pos.x - pos.x % regionChunks) ~/ regionChunks, z: (pos.z - pos.z % regionChunks) ~/ regionChunks);

  @override
  void apply(ChunkPos pos, ChunkMeshResult surface) {
    _chunks[pos] = [surface.solid, surface.cutout, surface.glow, surface.liquid];
    _rebuild(regionOf(pos));
  }

  @override
  void remove(ChunkPos pos) {
    if (_chunks.remove(pos) != null) _rebuild(regionOf(pos));
  }

  void _rebuild(ChunkPos region) {
    final old = _regions.remove(region);
    if (old != null) root.remove(old);
    final members = <(ChunkPos, List<MeshSurface>)>[
      for (var dx = 0; dx < regionChunks; dx++)
        for (var dz = 0; dz < regionChunks; dz++)
          if (_chunks[(x: region.x * regionChunks + dx, z: region.z * regionChunks + dz)] case final s?)
            ((x: dx, z: dz), s),
    ];
    if (members.isEmpty) return;
    final node = Node(name: 'region_${region.x}_${region.z}')
      ..position = Vector3(
        region.x * regionChunks * ChunkSize.sizeX.toDouble(),
        0,
        region.z * regionChunks * ChunkSize.sizeZ.toDouble(),
      );
    for (final (i, material) in [matSolid, matCutout, matGlow, matLiquid].indexed) {
      final surface = _merge([for (final (offset, s) in members) (offset, s[i])], material);
      if (surface != null) node.add(surface);
    }
    root.add(node);
    _regions[region] = node;
  }

  /// One node drawing [parts] (each at its chunk's offset in the region, in
  /// chunks) on [material], or null when they are all empty.
  Node? _merge(List<(ChunkPos, MeshSurface)> parts, Material material) {
    final m = MergedSurface.of(parts);
    if (m == null) return null;
    final geometry = MeshGeometry.fromArrays(
      positions: m.positions,
      normals: m.normals,
      colors: m.colors,
      texCoords1: m.light, // (sky / 15, block / 15)
      indices: m.indices,
      bounds: Aabb3.minMax(
        Vector3(0, m.minY, 0),
        Vector3(regionChunks * ChunkSize.sizeX.toDouble(), m.maxY, regionChunks * ChunkSize.sizeZ.toDouble()),
      ),
      retainCpuData: false,
    );
    return Node(mesh: Mesh(geometry, material))..shadowStatic = true;
  }
}
