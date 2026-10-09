import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import 'merged_surface.dart';
import 'packed_surface.dart';
import 'terrain_geometry.dart';
import 'terrain_material.dart';

/// voxel_core's chunks drawn with flutter_scene: the [ChunkMeshSink] a
/// [ChunkStreamer] hands finished meshes to. Chunks are drawn in regions of
/// [regionChunks] × [regionChunks]: one [Node] per region under [root], one
/// child per non-empty surface on its material. The three lit surfaces draw in
/// [TerrainGeometry]'s 16-byte packed vertex; the glow in the engine's own, its
/// light in the second UV set.
///
/// A region is one draw per surface where a chunk was one each, because
/// flutter_scene batches only draws of the identical geometry. The price is
/// that a chunk's mesh or removal rebuilds its region's geometry from the
/// surfaces of its chunks, which the view keeps: the lit ones packed the first
/// time a rebuild reads them, so a later rebuild moves words and never packs
/// again.
///
/// [apply] and [remove] only mark a region to rebuild; [rebuild], once a frame,
/// builds them within a time budget, so the chunks a streamer hands over
/// together are drawn over a few frames instead of in one long one, and a
/// region is built once however many of its chunks changed. Nothing is drawn
/// before [rebuild] runs.
///
/// [cull] hides the regions sight cannot reach from the camera through open
/// cells, by the [ChunkVisibility] each chunk's mesh carries
/// ([SectionOcclusion]). A hidden region's surfaces take [Node.layers] 0: the
/// colour and depth passes skip them, while they still cast into the shadow
/// map and leave its static cache alone, so a hill hidden behind the camera
/// still shades what is in view.
class VoxelChunkView implements ChunkMeshSink {
  /// A view with an empty [root] named [rootName]. Add [root] to a scene.
  VoxelChunkView({String rootName = 'World', this.regionChunks = 2})
    : assert(regionChunks >= 1, 'a region holds at least one chunk'),
      assert(
        regionChunks * ChunkSize.sizeX <= 255 && regionChunks * ChunkSize.sizeZ <= 255,
        'a packed terrain vertex spans 256 m',
      ),
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

  /// Microseconds [rebuild] spends a frame by default: a quarter of a 120 Hz
  /// frame.
  static const int rebuildBudgetUsec = 2000;

  /// Each meshed chunk's surfaces.
  final Map<ChunkPos, _ViewChunk> _chunks = {};

  /// Each region's node under [root], keyed by the region's position.
  final Map<ChunkPos, Node> _regions = {};

  /// Regions whose chunks changed since they were last built.
  final Set<ChunkPos> _dirty = {};

  /// The search [cull] runs, over the visibility of the chunks kept here; a
  /// chunk with no mesh is crossed as open.
  late final SectionOcclusion _occlusion = SectionOcclusion((pos) => _chunks[pos]?.visibility);

  /// Whether [cull] has run: before it, every region draws.
  bool _culled = false;

  /// The corners of the chunks kept here, inclusive; null when a chunk came or
  /// left since they were last found.
  (ChunkPos, ChunkPos)? _span;

  /// What packing and building cost, in microseconds a vertex, as measured on
  /// the rebuilds so far; null before the first.
  double? _packUsPerVertex, _buildUsPerVertex;

  /// Chunks with a mesh in the view, drawn or waiting for [rebuild].
  int get chunkCount => _chunks.length;

  /// Regions with a node under [root].
  int get regionCount => _regions.length;

  /// Regions waiting for [rebuild].
  int get pendingRegions => _dirty.length;

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

  /// Keeps [surface] for chunk [pos] and marks its region to rebuild.
  @override
  void apply(ChunkPos pos, ChunkMeshResult surface) {
    if (_chunks[pos] == null) _span = null;
    _chunks[pos] = _ViewChunk(surface);
    _dirty.add(regionOf(pos));
    _occlusion.markChanged(pos);
  }

  /// Drops chunk [pos] and marks its region to rebuild.
  @override
  void remove(ChunkPos pos) {
    if (_chunks.remove(pos) == null) return;
    _dirty.add(regionOf(pos));
    _occlusion.markChanged(pos);
    _span = null;
  }

  /// Hides the regions sight cannot reach from [eye] through open cells, and
  /// shows the ones it can: a region draws when any of its chunks was reached.
  /// The search runs again only when [eye] entered another 16-tall section, or
  /// a chunk came, changed or left since the last one; otherwise this costs
  /// nothing. A region [rebuild] builds later takes the last search's result.
  /// Once a frame, after [rebuild]. True when the search ran.
  bool cull(Vector3 eye) {
    final camera = ChunkStreamer.chunkOfXZ(eye.x.floor(), eye.z.floor());
    final (lo, hi) = _span ??= _spanOfChunks();
    final min = (x: math.min(lo.x, camera.x), z: math.min(lo.z, camera.z));
    final max = (x: math.max(hi.x, camera.x), z: math.max(hi.z, camera.z));
    if (!_occlusion.update(camera, SectionOcclusion.sectionAt(eye.y), min: min, max: max)) return false;
    _culled = true;
    for (final MapEntry(key: region, value: node) in _regions.entries) {
      _show(node, _reached(region));
    }
    return true;
  }

  /// The corners of the chunks kept here; an empty view spans nothing, which
  /// [cull]'s window around the camera's chunk then covers.
  (ChunkPos, ChunkPos) _spanOfChunks() {
    var minX = 1 << 30, minZ = 1 << 30, maxX = -(1 << 30), maxZ = -(1 << 30);
    for (final pos in _chunks.keys) {
      minX = math.min(minX, pos.x);
      minZ = math.min(minZ, pos.z);
      maxX = math.max(maxX, pos.x);
      maxZ = math.max(maxZ, pos.z);
    }
    return ((x: minX, z: minZ), (x: maxX, z: maxZ));
  }

  /// Whether the last search reached a chunk of [region] that has a mesh.
  bool _reached(ChunkPos region) {
    final reached = _occlusion.reached;
    for (var dx = 0; dx < regionChunks; dx++) {
      for (var dz = 0; dz < regionChunks; dz++) {
        final pos = (x: region.x * regionChunks + dx, z: region.z * regionChunks + dz);
        if (_chunks.containsKey(pos) && reached.contains(pos)) return true;
      }
    }
    return false;
  }

  /// Puts a region's node and its surfaces on the default layer when [shown],
  /// on none when not. Their [Node.visible] and shadow settings stay as built.
  static void _show(Node region, bool shown) {
    final layers = shown ? kRenderLayerDefault : 0;
    region.layers = layers;
    for (final surface in region.children) {
      surface.layers = layers;
    }
  }

  /// Builds the regions whose chunks changed, the nearest to chunk [near] first,
  /// while the next one's predicted cost fits in what is left of [budgetUsec];
  /// the rest wait for the next call. The first region is built whatever it
  /// costs, so the view keeps up; a region left with no chunk drops its node and
  /// costs nothing. Once a frame.
  void rebuild(ChunkPos near, {int budgetUsec = rebuildBudgetUsec}) {
    if (_dirty.isEmpty) return;
    final watch = Stopwatch()..start();
    final centre = regionOf(near);
    int d2(ChunkPos r) => (r.x - centre.x) * (r.x - centre.x) + (r.z - centre.z) * (r.z - centre.z);
    final order = _dirty.toList()..sort((a, b) => d2(a).compareTo(d2(b)));
    var built = 0;
    for (final region in order) {
      final members = _members(region);
      if (members.isNotEmpty) {
        if (built > 0 && watch.elapsedMicroseconds + _predictUs(members) >= budgetUsec) continue;
        _build(region, members);
        built += 1;
      } else {
        final old = _regions.remove(region);
        if (old != null) root.remove(old);
      }
      _dirty.remove(region);
    }
  }

  /// The chunks of [region] with a mesh, each with its offset in the region.
  List<(ChunkPos, _ViewChunk)> _members(ChunkPos region) => [
    for (var dx = 0; dx < regionChunks; dx++)
      for (var dz = 0; dz < regionChunks; dz++)
        if (_chunks[(x: region.x * regionChunks + dx, z: region.z * regionChunks + dz)] case final c?)
          ((x: dx, z: dz), c),
  ];

  /// What building a region of [members] should cost, by the rates measured so far.
  double _predictUs(List<(ChunkPos, _ViewChunk)> members) {
    var toPack = 0, all = 0;
    for (final (_, c) in members) {
      if (!c.packed) toPack += c.litVertexCount;
      all += c.vertexCount;
    }
    return toPack * (_packUsPerVertex ?? 0.0) + all * (_buildUsPerVertex ?? 0.0);
  }

  /// A rate after a sample of it: the sample alone at first, then a running mean.
  static double _meanWith(double? rate, double sample) => rate == null ? sample : rate + (sample - rate) * 0.2;

  void _build(ChunkPos region, List<(ChunkPos, _ViewChunk)> members) {
    final watch = Stopwatch()..start();
    var packed = 0;
    for (final (_, c) in members) {
      if (c.packed) continue;
      packed += c.litVertexCount;
      c.pack();
    }
    final packUs = watch.elapsedMicroseconds;
    if (packed > 0) _packUsPerVertex = _meanWith(_packUsPerVertex, packUs / packed);
    final old = _regions.remove(region);
    if (old != null) root.remove(old);
    final node = Node(name: 'region_${region.x}_${region.z}')
      ..position = Vector3(
        region.x * regionChunks * ChunkSize.sizeX.toDouble(),
        0,
        region.z * regionChunks * ChunkSize.sizeZ.toDouble(),
      );
    List<(ChunkPos, PackedSurface)> lit(PackedSurface? Function(_ViewChunk) of) => [
      for (final (offset, c) in members)
        if (of(c) case final packed?) (offset, packed),
    ];
    for (final surface in [
      _mergeLit(lit((c) => c.solid), matSolid),
      _mergeLit(lit((c) => c.cutout), matCutout),
      _mergeGlow([for (final (offset, c) in members) (offset, c.glow)]),
      _mergeLit(lit((c) => c.liquid), matLiquid),
    ]) {
      if (surface != null) node.add(surface);
    }
    _show(node, !_culled || _reached(region));
    root.add(node);
    _regions[region] = node;
    var vertices = 0;
    for (final (_, c) in members) {
      vertices += c.vertexCount;
    }
    if (vertices > 0) _buildUsPerVertex = _meanWith(_buildUsPerVertex, (watch.elapsedMicroseconds - packUs) / vertices);
  }

  /// The region's box in its own frame, from the heights its vertices span.
  Aabb3 _bounds(double minY, double maxY) => Aabb3.minMax(
    Vector3(0, minY, 0),
    Vector3(regionChunks * ChunkSize.sizeX.toDouble(), maxY, regionChunks * ChunkSize.sizeZ.toDouble()),
  );

  /// One node drawing lit [parts] (each at its chunk's offset in the region, in
  /// chunks) in the packed terrain vertex on [material], or null when there are
  /// none.
  Node? _mergeLit(List<(ChunkPos, PackedSurface)> parts, TerrainMaterial material) {
    final m = PackedSurface.merge(parts);
    if (m == null) return null;
    return Node(mesh: Mesh(TerrainGeometry(m, _bounds(m.minY, m.maxY)), material))..shadowStatic = true;
  }

  /// One node drawing the glow [parts] on [matGlow], or null when they are all
  /// empty. Their colour keeps each block's variation baked in, which can pass
  /// 1.0 where the packed vertex stores 0..1, so they stay in the engine's vertex.
  Node? _mergeGlow(List<(ChunkPos, MeshSurface)> parts) {
    final m = MergedSurface.of(parts);
    if (m == null) return null;
    final geometry = MeshGeometry.fromArrays(
      positions: m.positions,
      normals: m.normals,
      colors: m.colors,
      texCoords1: m.light, // (sky / 15, block / 15)
      indices: m.indices,
      bounds: _bounds(m.minY, m.maxY),
      retainCpuData: false,
    );
    return Node(mesh: Mesh(geometry, matGlow))..shadowStatic = true;
  }
}

/// A chunk as [VoxelChunkView] keeps it: its mesh as the engine made it until a
/// rebuild first reads it ([pack]), then its lit surfaces packed and their
/// floats let go; the glow as the engine meshed it throughout.
class _ViewChunk {
  _ViewChunk(ChunkMeshResult mesh)
    : _mesh = mesh,
      glow = mesh.glow,
      visibility = mesh.visibility,
      litVertexCount = mesh.solid.vertexCount + mesh.cutout.vertexCount + mesh.liquid.vertexCount,
      vertexCount = mesh.solid.vertexCount + mesh.cutout.vertexCount + mesh.liquid.vertexCount + mesh.glow.vertexCount;

  /// The mesh whose lit surfaces are not packed yet; null once they are.
  ChunkMeshResult? _mesh;

  /// Drawn in the engine's vertex, never packed.
  final MeshSurface glow;

  /// Which faces of each section its open cells join, for [VoxelChunkView.cull].
  final ChunkVisibility visibility;

  /// Vertices of the solid, cutout and liquid surfaces.
  final int litVertexCount;

  /// Vertices of every surface, the glow's included.
  final int vertexCount;

  PackedSurface? _solid, _cutout, _liquid;

  /// Whether the lit surfaces are packed.
  bool get packed => _mesh == null;

  /// The packed solid surface, null when empty.
  PackedSurface? get solid => _read(_solid);

  /// The packed cutout surface, null when empty.
  PackedSurface? get cutout => _read(_cutout);

  /// The packed liquid surface, null when empty.
  PackedSurface? get liquid => _read(_liquid);

  PackedSurface? _read(PackedSurface? surface) {
    assert(packed, 'a chunk is packed before its region reads it');
    return surface;
  }

  /// Packs the lit surfaces, once.
  void pack() {
    final mesh = _mesh;
    if (mesh == null) throw StateError('a chunk is packed once');
    _solid = PackedSurface.of(mesh.solid);
    _cutout = PackedSurface.of(mesh.cutout);
    _liquid = PackedSurface.of(mesh.liquid);
    _mesh = null;
  }
}
